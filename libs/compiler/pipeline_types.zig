//! Shared compiler backend boundaries for native SDKs and build-time workers.

const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const content = @import("content");
const image = @import("image");
const lock = @import("lock.zig");
const cache = @import("cache.zig");

pub const IntegrationError = error{ ContractUnavailable, ContractRejected, OutOfMemory, Canceled };
pub const Error = program.model.Error || program.wit.Error || lock.Error || cache.Error ||
    image.Error || IntegrationError || error{
    CompileIo,
    SigningRequired,
    CompileInputMissing,
    InputTypeAmbiguous,
    AuthoringResolvedType,
};
pub const Stage = enum {
    model,
    lock,
    content,
    capability,
    binding,
    emission,
    assembly,
    signing,
    publish,
};
pub const Code = enum {
    invalid_model,
    identity_mismatch,
    invalid_content,
    capability_mismatch,
    type_mismatch,
    input_missing,
    canceled,
    io_failure,
    output_limit,
    signing_required,
};
pub const Location = struct { file: []const u8, line: u32, column: u32 };
pub const SourceMap = struct { object: []const u8, source: Location };
pub const SourceMapFile = struct { schema: u32 = 1, locations: []const SourceMap };
pub const ObjectKind = enum {
    product,
    library,
    container,
    call,
    observation,
    input,
    root,
    grant,
    @"author-input",
};
pub const Diagnostic = struct {
    stage: Stage,
    code: Code,
    object: []const u8,
    kind: ObjectKind,
    cause: []const u8,
    source: ?Location = null,
};
pub const Input = struct {
    id: []const u8,
    source: content.Source,
    /// Optional locator for subprocess inspectors. Build supplies its private captured path.
    path: ?[]const u8 = null,
};
pub const Inspector = struct {
    context: ?*anyopaque = null,
    tool_id: ?[]const u8 = null,
    inspect: *const fn (
        ?*anyopaque,
        std.mem.Allocator,
        std.Io,
        program.model.Library,
        Input,
        ?Input,
    ) IntegrationError!program.wit.Inspection,
};
pub const HostInterface = struct {
    primitive: program.profile.Requirement,
    interface: []const u8,
    functions: []const program.wit.NamedItem,
};
pub const Finalizer = struct {
    context: ?*anyopaque = null,
    tool_id: ?[]const u8 = null,
    /// Must sign and verify the chosen native/publisher profile before returning success.
    finalize: *const fn (
        ?*anyopaque,
        std.mem.Allocator,
        std.Io,
        []const u8,
        image.Format,
        ?Input,
    ) IntegrationError!void,
};
pub const Request = struct {
    product: program.model.Product,
    /// Independently resolved, authenticated metadata for the locked runtime package.
    runtime_profile: program.profile.Profile,
    inputs: []const Input,
    lock: lock.Lock,
    runtime_id: []const u8,
    inspector: ?Inspector = null,
    hosts: []const HostInterface = &.{},
    locations: []const SourceMap = &.{},
    compiler_version: []const u8 = "niobium-compiler-v2",
    cancel: ?*const std.atomic.Value(bool) = null,
    cache: ?cache.Cache = null,
};
pub const Compiled = struct {
    product: program.model.Product,
    bytes: []const u8,
    sha256: contracts.Digest,
    cache_hit: bool,
};
pub const Output = struct {
    /// Private workspace, also the destination filesystem for atomic publication.
    dir: std.Io.Dir,
    name: []const u8,
    finalizer: ?Finalizer = null,
};
pub const Built = struct {
    program_sha256: contracts.Digest,
    payload: content.ContainerRef,
    setup_sha256: contracts.Digest,
    bytes: u64,
    cache_hit: bool,
};
pub const LibraryContract = struct { id: []const u8, inspection: program.wit.Inspection };

pub fn canceled(request: Request) Error!void {
    if (request.cancel) |flag| if (flag.load(.acquire)) return error.Canceled;
}

pub fn report(
    diagnostic: *?Diagnostic,
    request: Request,
    stage: Stage,
    code: Code,
    kind: ObjectKind,
    object: []const u8,
    err: Error,
) void {
    var location: ?Location = null;
    for (request.locations) |item| {
        const prefix = @tagName(kind);
        if (item.object.len == prefix.len + 1 + object.len and
            std.mem.startsWith(u8, item.object, prefix) and item.object[prefix.len] == ':' and
            std.mem.eql(u8, object, item.object[prefix.len + 1 ..]))
        {
            location = item.source;
            break;
        }
    }
    diagnostic.* = .{
        .stage = stage,
        .code = code,
        .object = object,
        .kind = kind,
        .cause = @errorName(err),
        .source = location,
    };
}

pub fn input(request: Request, id: []const u8) Error!Input {
    return program.find(Input, request.inputs, id) orelse error.CompileInputMissing;
}

pub fn tool(request: Request, id: ?[]const u8) Error!?Input {
    const name = id orelse return null;
    const expected = program.find(lock.Input, request.lock.inputs, name) orelse
        return error.CompileInputMissing;
    if (expected.kind != .tool) return error.LockMismatch;
    return try input(request, name);
}
