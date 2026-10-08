//! A runtime's profile is coupled to its locked publication, never inferred by executing it.
const std = @import("std");
const program = @import("program");
const contracts = @import("contracts");
const lock = @import("lock.zig");
pub const Error = lock.Error || program.profile.Error;
pub const Package = struct {
    schema: u32 = 1,
    version: []const u8,
    template_sha256: []const u8,
    template_bytes: u64,
    profile: program.profile.Profile,
};

/// Acquisition must establish publisher authority separately from this identity check.
pub fn resolve(
    arena: std.mem.Allocator,
    inputs: lock.Lock,
    runtime_id: []const u8,
    metadata_id: []const u8,
    metadata: []const u8,
) Error!Package {
    try lock.validate(inputs);
    const runtime = program.find(lock.Input, inputs.inputs, runtime_id) orelse
        return error.LockMissing;
    const published = program.find(lock.Input, inputs.inputs, metadata_id) orelse
        return error.LockMissing;
    if (runtime.kind != .runtime or published.kind != .runtime_metadata)
        return error.LockMismatch;
    var linked = false;
    for (runtime.dependencies) |id| {
        if (std.mem.eql(u8, id, metadata_id)) linked = true;
    }
    if (!linked) return error.LockMismatch;
    try lock.verify(published, metadata);
    const package = try decode(arena, metadata);
    if (!std.mem.eql(u8, package.template_sha256, runtime.sha256) or
        package.template_bytes != runtime.bytes or package.profile.target != runtime.target or
        !std.mem.eql(u8, package.version, runtime.version)) return error.LockMismatch;
    return package;
}

pub fn decode(arena: std.mem.Allocator, bytes: []const u8) Error!Package {
    const package = try contracts.json.decode(Package, arena, bytes, .{
        .max_bytes = contracts.limits.default.manifest_bytes,
        .max_schema = 1,
    });
    if (package.schema != 1 or package.template_bytes == 0 or
        package.template_bytes > contracts.limits.default.native_image_bytes)
        return error.LockMismatch;
    if (package.version.len == 0 or package.version.len > 128) return error.ProgramInvalid;
    try program.validation.inputValue(package.version, .{});
    try lock.digest(package.template_sha256);
    try program.profile.validate(package.profile);
    return package;
}

test "N2-PROFILE-02: locked metadata must describe the exact runtime publication" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const digest = try program.digest(a, "template");
    const bytes = try std.json.Stringify.valueAlloc(a, Package{
        .version = "2",
        .template_sha256 = digest,
        .template_bytes = 8,
        .profile = .{ .id = "niobium.user", .target = .@"x86_64-linux", .primitives = &.{} },
    }, .{});
    var entries = [_]lock.Input{
        .{
            .id = "runtime",
            .kind = .runtime,
            .version = "2",
            .origin = "template",
            .sha256 = digest,
            .bytes = 8,
            .target = .@"x86_64-linux",
            .dependencies = &.{"metadata"},
        },
        .{
            .id = "metadata",
            .kind = .runtime_metadata,
            .version = "2",
            .origin = "metadata",
            .sha256 = try program.digest(a, bytes),
            .bytes = bytes.len,
        },
    };
    const package = try resolve(a, .{ .inputs = &entries }, "runtime", "metadata", bytes);
    try std.testing.expectEqual(.@"x86_64-linux", package.profile.target);
    entries[0].target = .@"x86_64-windows";
    try std.testing.expectError(
        error.LockMismatch,
        resolve(a, .{ .inputs = &entries }, "runtime", "metadata", bytes),
    );
    entries[0].target = .@"x86_64-linux";
    entries[0].dependencies = &.{};
    try std.testing.expectError(
        error.LockMismatch,
        resolve(a, .{ .inputs = &entries }, "runtime", "metadata", bytes),
    );
}
