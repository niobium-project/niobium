//! A runtime's profile is coupled to its locked publication, never inferred by executing it.
const std = @import("std");
const program = @import("program");
const contracts = @import("contracts");
const lock = @import("lock.zig");
pub const Error = lock.Error || program.profile.Error;
/// Versioned publisher declarations; machine headers cannot establish a minimum instruction set.
pub const NativeProfile = enum {
    @"aarch64-macos-baseline-v1",
    @"x86_64-linux-gnu-baseline-v1",
    @"x86_64-linux-musl-baseline-v1",
    @"x86_64-windows-gnu-baseline-v1",

    pub fn target(profile: NativeProfile) program.profile.Target {
        return switch (profile) {
            .@"aarch64-macos-baseline-v1" => .@"aarch64-macos",
            .@"x86_64-linux-gnu-baseline-v1", .@"x86_64-linux-musl-baseline-v1" => .@"x86_64-linux",
            .@"x86_64-windows-gnu-baseline-v1" => .@"x86_64-windows",
        };
    }
};
pub const Package = struct {
    schema: u32,
    version: []const u8,
    template_sha256: []const u8,
    template_bytes: u64,
    native_profile: NativeProfile,
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
        !std.mem.eql(u8, package.version, runtime.version) or
        !std.mem.eql(u8, package.version, published.version)) return error.LockMismatch;
    return package;
}

pub fn decode(arena: std.mem.Allocator, bytes: []const u8) Error!Package {
    const package = try contracts.json.decode(Package, arena, bytes, .{
        .max_bytes = contracts.limits.default.manifest_bytes,
        .max_schema = 2,
    });
    if (package.schema != 2 or package.template_bytes == 0 or
        package.template_bytes > contracts.limits.default.native_image_bytes)
        return error.LockMismatch;
    if (package.version.len == 0 or package.version.len > 128) return error.ProgramInvalid;
    try program.validation.inputValue(package.version, .{});
    try lock.digest(package.template_sha256);
    try program.profile.validate(package.profile);
    if (package.native_profile.target() != package.profile.target) return error.ProfileMismatch;
    return package;
}

test "N2-PROFILE-02: locked metadata must describe the exact runtime publication" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const digest = try program.digest(a, "template");
    const bytes = try std.json.Stringify.valueAlloc(a, Package{
        .schema = 2,
        .version = "2",
        .template_sha256 = digest,
        .template_bytes = 8,
        .native_profile = .@"x86_64-linux-gnu-baseline-v1",
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
    const altered = try std.mem.replaceOwned(u8, a, bytes, "linux-gnu", "linux-musl");
    try std.testing.expectError(
        error.LockMismatch,
        resolve(a, .{ .inputs = &entries }, "runtime", "metadata", altered),
    );
    entries[1].version = "1";
    try std.testing.expectError(
        error.LockMismatch,
        resolve(a, .{ .inputs = &entries }, "runtime", "metadata", bytes),
    );
    entries[1].version = "2";
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

test "N2-PROFILE-03: publication requires an explicit native CPU contract" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const bytes =
        \\{"schema":1,"version":"1","template_sha256":
        \\"0000000000000000000000000000000000000000000000000000000000000000",
        \\"template_bytes":1,"profile":{"id":"niobium.user",
        \\"target":"x86_64-linux","primitives":[]}}
    ;
    try std.testing.expectError(error.JsonMissingField, decode(arena.allocator(), bytes));
}

test "N2-PROFILE-03: native publication versions and targets fail closed" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var package: Package = .{
        .schema = 2,
        .version = "1",
        .template_sha256 = try program.digest(a, "template"),
        .template_bytes = 8,
        .native_profile = .@"x86_64-linux-gnu-baseline-v1",
        .profile = .{ .id = "niobium.user", .target = .@"x86_64-linux", .primitives = &.{} },
    };
    const bytes = try std.json.Stringify.valueAlloc(a, package, .{});
    try std.testing.expectEqual(package.native_profile, (try decode(a, bytes)).native_profile);
    const unknown = try std.mem.replaceOwned(u8, a, bytes, "baseline-v1", "baseline-v9");
    try std.testing.expectError(error.JsonType, decode(a, unknown));
    const missing = try std.mem.replaceOwned(u8, a, bytes, "\"schema\":2,", "");
    try std.testing.expectError(error.JsonMissingField, decode(a, missing));
    package.schema = 1;
    try std.testing.expectError(
        error.LockMismatch,
        decode(a, try std.json.Stringify.valueAlloc(a, package, .{})),
    );
    package.schema = 3;
    try std.testing.expectError(
        error.UnsupportedSchema,
        decode(a, try std.json.Stringify.valueAlloc(a, package, .{})),
    );
    package.schema = 2;
    package.native_profile = .@"x86_64-windows-gnu-baseline-v1";
    try std.testing.expectError(
        error.ProfileMismatch,
        decode(a, try std.json.Stringify.valueAlloc(a, package, .{})),
    );
}
