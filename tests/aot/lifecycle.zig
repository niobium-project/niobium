//! Real filesystem witnesses for library output, reconfiguration and explicit model migration.

const std = @import("std");
const program = @import("program");
const runtime = @import("runtime");
const World = @import("world.zig").World;
const expect = @import("world.zig").expect;
const Setups = @import("packaging.zig").Setups;

pub fn verify(w: *World, setups: Setups) !void {
    try fileProduct(w, setups.files);
    const root = try w.path("installation-environment");
    try w.command(&.{ setups.v1, "install", "--root", root, "--set", "sdk=nightly" }, true);
    try environment(w, root, "nightly", "");
    const initial = (try w.status(w.tools.runtime, root, "status")).state orelse
        return error.MissingState;
    try snapshot(w, initial, 1, 1, "nightly", 0);
    try w.command(&.{ setups.v1, "apply", "--root", root, "--set", "sdk=beta" }, true);
    try environment(w, root, "beta", "1:nightly");
    try rejectionPreservesState(w, setups, root);
    try w.command(&.{ setups.v2, "apply", "--root", root, "--set", "sdk=preview" }, true);
    try environment(w, root, "preview", "2:beta");
    const updated = (try w.status(w.tools.runtime, root, "status")).state orelse
        return error.MissingState;
    try snapshot(w, updated, 2, 3, "preview", 2);
    try w.command(&.{ setups.v2, "apply", "--root", root }, true);
    try environment(w, root, "preview", "2:preview");
    const reapplied = (try w.status(w.tools.runtime, root, "status")).state orelse
        return error.MissingState;
    try snapshot(w, reapplied, 2, 4, "preview", 2);
    try w.command(&.{ setups.v2, "uninstall", "--root", root }, true);
    try expect((try w.status(w.tools.runtime, root, "status")).state == null);
    try expect(!try w.exists(try std.fs.path.join(w.arena, &.{ root, "current/toolchain.env" })));
    try w.case("N2-LIB-01", "product-library-inputs-facts-state", "PASS");
    try w.case("N2-LIFE-01", "install-reconfigure-update-uninstall", "PASS");
    try w.case("N2-MIG-01", "explicit-state-and-model-migration", "PASS");
}

fn fileProduct(w: *World, setup: []const u8) !void {
    const root = try w.path("installation-files");
    try w.command(&.{ setup, "install", "--root", root }, true);
    const path = try std.fs.path.join(w.arena, &.{ root, "current/README.txt" });
    try w.expectFile(path, "Installed through a capability library.\n");
    const status = (try w.status(w.tools.runtime, root, "status")).state orelse
        return error.MissingState;
    try expect(std.mem.eql(u8, status.product_id, "example.files"));
    try expect(status.generation == 1);
    const user_old = try std.fs.path.join(w.arena, &.{ root, "generations/1/user.txt" });
    try w.write(user_old, "User-owned file in the old generation.\n");
    try w.command(&.{ setup, "apply", "--root", root }, true);
    try w.expectFile(user_old, "User-owned file in the old generation.\n");
    const user_new = try std.fs.path.join(w.arena, &.{ root, "generations/2/user.txt" });
    try w.write(user_new, "User-owned file in the current generation.\n");
    try w.command(&.{ setup, "uninstall", "--root", root }, true);
    try expect(!try w.exists(path));
    try expect((try w.status(w.tools.runtime, root, "status")).state == null);
    try w.expectFile(user_old, "User-owned file in the old generation.\n");
    try w.expectFile(user_new, "User-owned file in the current generation.\n");
}

fn rejectionPreservesState(w: *World, setups: Setups, root: []const u8) !void {
    const state_path = try std.fs.path.join(w.arena, &.{ root, "installation.json" });
    const before = try w.read(state_path);
    const changed = try w.run(&.{ setups.changed_release, "apply", "--root", root }, false);
    try expect(std.mem.indexOf(u8, changed.stderr, "ReleaseIdentityMismatch") != null);
    try w.expectFile(state_path, before);
    for ([_][]const u8{ setups.missing, setups.missing_library }) |setup| {
        const rejected = try w.run(&.{
            setup, "apply", "--root", root, "--set", "sdk=must-not-appear",
        }, false);
        try expect(std.mem.indexOf(u8, rejected.stderr, "UpgradeUnsupported") != null);
        try w.expectFile(state_path, before);
        try environment(w, root, "beta", "1:nightly");
    }
    try expect(!try w.exists(try std.fs.path.join(w.arena, &.{ root, "pending.json" })));
    const unknown = try w.run(&.{
        setups.v1, "apply", "--root", root, "--set", "unknown=must-not-appear",
    }, false);
    try expect(std.mem.indexOf(u8, unknown.stderr, "InputUnknown") != null);
    try w.expectFile(state_path, before);
    for ([_][]const u8{ "apply", "uninstall" }) |action| {
        const mismatch = try w.run(&.{ setups.files, action, "--root", root }, false);
        try expect(std.mem.indexOf(u8, mismatch.stderr, "ProductMismatch") != null);
        try w.expectFile(state_path, before);
        try environment(w, root, "beta", "1:nightly");
    }
}

pub fn environment(w: *World, root: []const u8, sdk: []const u8, previous: []const u8) !void {
    const expected = try w.arena.print("sdk={s}\nos=macos\narch=aarch64\nprevious={s}\n", .{
        sdk, previous,
    });
    try w.expectFile(try std.fs.path.join(w.arena, &.{ root, "current/toolchain.env" }), expected);
}

pub fn snapshot(
    w: *World,
    value: runtime.state.Snapshot,
    version: u32,
    generation: u64,
    sdk: []const u8,
    migration_count: usize,
) !void {
    try expect(value.model_version == version);
    try expect(value.release_sequence == version);
    try expect(value.generation == generation);
    try expect(value.inputs.len == 1);
    try expect(value.instances.len == 1);
    try expect(value.migrations.len == migration_count);
    try expect(std.mem.eql(u8, value.inputs[0].value, sdk));
    try expect(value.instances[0].version == version);
    const state = try program.decodeHex(w.arena, value.instances[0].data_hex);
    const expected = try w.arena.print("{d}:{s}", .{ version, sdk });
    try expect(std.mem.eql(u8, state, expected));
    if (migration_count != 0) {
        try expect(std.mem.eql(u8, value.migrations[0].owner, "@product"));
        try expect(std.mem.eql(u8, value.migrations[1].owner, "environment"));
        for (value.migrations) |migration| {
            try expect(migration.from == 1 and migration.to == 2);
            try expect(migration.implementation_sha256.len == 64);
        }
    }
}
