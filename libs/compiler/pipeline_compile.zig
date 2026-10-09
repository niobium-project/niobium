//! Shared compiler stages. All authoring frontends consume this backend.

const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const cache = @import("cache.zig");
const sources = @import("pipeline_sources.zig");
const types = @import("pipeline_types.zig");

pub const Request = types.Request;
pub const Input = types.Input;
pub const Inspector = types.Inspector;
pub const HostInterface = types.HostInterface;
pub const Finalizer = types.Finalizer;
pub const Output = types.Output;
pub const Compiled = types.Compiled;
pub const Built = types.Built;
pub const Diagnostic = types.Diagnostic;
pub const SourceMap = types.SourceMap;
pub const IntegrationError = types.IntegrationError;
pub const Error = types.Error;

pub fn compile(
    arena: std.mem.Allocator,
    io: std.Io,
    request: Request,
    diagnostic: *?Diagnostic,
) Error!Compiled {
    return prepare(arena, io, request, diagnostic, false);
}

/// `canonical_checked` is internal to build, after verified private normalization.
pub fn prepare(
    arena: std.mem.Allocator,
    io: std.Io,
    request: Request,
    diagnostic: *?Diagnostic,
    canonical_checked: bool,
) Error!Compiled {
    diagnostic.* = null;
    try types.canceled(request);
    if (request.hosts.len > contracts.limits.default.program_items) return error.ProgramLimit;
    try @import("pipeline_source_map.zig").validate(.{ .locations = request.locations });
    const normalized = program.model.normalize(arena, request.product) catch |err| {
        types.report(
            diagnostic,
            request,
            .model,
            .invalid_model,
            .product,
            request.product.id,
            err,
        );
        return err;
    };
    try sources.validate(arena, io, request, diagnostic);
    if (!canonical_checked) for (request.product.containers) |container| {
        const input = try types.input(request, container.id);
        var buffer: [4096]u8 = undefined; // SAFETY: discard sink consumes written data only.
        var sink: std.Io.Writer.Discarding = .init(&buffer);
        sources.canonical(arena, io, input.source, &sink.writer, container.reference) catch |err| {
            types.report(
                diagnostic,
                request,
                .content,
                .invalid_content,
                .container,
                container.id,
                err,
            );
            return err;
        };
    };
    var binding_request = request;
    binding_request.product = normalized;
    const bound = try @import("pipeline_bind.zig").bind(arena, io, binding_request, diagnostic);
    try types.canceled(request);
    const author_bytes = try program.model.encode(arena, normalized);
    var author_digest: contracts.Digest = undefined; // SAFETY: hash initializes every byte.
    std.crypto.hash.sha2.Sha256.hash(author_bytes, &author_digest, .{});
    const bytes = try program.model.encode(arena, bound);
    var digest: contracts.Digest = undefined; // SAFETY: hash initializes every byte.
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hit = try emitted(arena, io, request, normalized.profile, author_digest, bytes, digest);
    return .{
        .product = try program.model.decode(arena, bytes),
        .bytes = bytes,
        .sha256 = digest,
        .cache_hit = hit,
    };
}

fn emitted(
    arena: std.mem.Allocator,
    io: std.Io,
    request: Request,
    normalized_profile: program.profile.Profile,
    author_digest: contracts.Digest,
    bytes: []const u8,
    digest: contracts.Digest,
) Error!bool {
    var store = request.cache orelse return false;
    if (request.cancel) |flag| store.cancel = flag;
    const profile = try std.json.Stringify.valueAlloc(arena, normalized_profile, .{});
    const key = try cache.key(arena, .{
        .compiler_version = request.compiler_version,
        .stage = .encode,
        .target = request.product.target,
        .model_sha256 = &contracts.ids.hexDigest(author_digest),
        .profile_sha256 = try program.digest(arena, profile),
        .options_sha256 = try program.digest(arena, "pax-v1;wit-component-v1;program-v2"),
        .inputs = request.lock,
    });
    if (try store.get(key)) |hit| {
        defer hit.close(io);
        if (hit.bytes != bytes.len or !std.mem.eql(
            u8,
            &hit.sha256,
            &digest,
        )) return error.CacheConflict;
        return true;
    }
    try store.put(key, .{ .bytes = bytes });
    return false;
}

test {
    _ = @import("pipeline_test.zig");
}
