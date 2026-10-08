//! Resource ceilings are checked before any durable content-addressed copy is published.
const std = @import("std");
const program = @import("program");
const platform = @import("platform");
const kernel = @import("kernel");
const access = @import("access");
const content = @import("content");
const Fixture = @import("fixture.zig").Fixture;
const io = std.testing.io;

test "N2-KERNEL-14 byte ceiling rejects before CAS publication" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var fixture = try Fixture.init(a, io, temp.dir, 1);
    var host = platform.Host.init(io, .{ .env = .{}, .system_managers = false });
    var options = try fixture.options(&host, .install);
    const grants = try a.dupe(program.model.Grant, options.model.?.grants);
    grants[0].max_bytes = 1;
    options.model.?.grants = grants;
    try std.testing.expectError(error.KernelLimit, kernel.run(options));
    const cas = try std.fs.path.join(a, &.{ fixture.roots[0].path, ".niobium-v2/cas" });
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().openDir(io, cas, .{}));
}

test "N2-KERNEL-15 entry ceiling includes synthesized prefix parents" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var fixture = try Fixture.init(a, io, temp.dir, 1);
    fixture.prefix = "one/two";
    var host = platform.Host.init(io, .{ .env = .{}, .system_managers = false });
    var options = try fixture.options(&host, .install);
    const grants = try a.dupe(program.model.Grant, options.model.?.grants);
    grants[0].max_entries = 2;
    options.model.?.grants = grants;
    try std.testing.expectError(error.KernelLimit, kernel.run(options));
    const cas = try std.fs.path.join(a, &.{ fixture.roots[0].path, ".niobium-v2/cas" });
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().openDir(io, cas, .{}));
    grants[0].max_entries = 4;
    const installed = try kernel.run(options);
    try std.testing.expectEqual(@as(usize, 4), installed.state.?.roots[0].resources.len);
}

test "N2-KERNEL-15 ancestors outside the grant remain private host scaffolds" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var fixture = try Fixture.init(a, io, temp.dir, 1);
    fixture.prefix = "one/two";
    fixture.directory_policy.everyone = .{ .read = true, .write = true };
    var host = platform.Host.init(io, .{ .env = .{}, .system_managers = false });
    var options = try fixture.options(&host, .install);
    const grants = try a.dupe(program.model.Grant, options.model.?.grants);
    grants[0].prefix = "one/two";
    grants[0].directory_access = fixture.directory_policy;
    options.model.?.grants = grants;
    const installed = try kernel.run(options);
    const resources = installed.state.?.roots[0].resources;
    try std.testing.expectEqualStrings("one", resources[0].path);
    try std.testing.expect(access.privatePolicy(.directory).everyone.bits() ==
        resources[0].policy.everyone.bits());
    try std.testing.expectEqualStrings("one/two", resources[1].path);
    try std.testing.expect(resources[1].policy.everyone.write);
    const parent = try std.fs.path.join(a, &.{ fixture.roots[0].path, "current/one" });
    const directory = try std.Io.Dir.cwd().openDir(io, parent, .{});
    defer directory.close(io);
    const observed = try access.inspect(a, io, access.directoryFile(directory));
    try std.testing.expect(!observed.policy.everyone.write);
}

test "N2-KERNEL-18 Windows rejects unsafe native link syntax before CAS writes" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var fixture = try Fixture.init(a, io, temp.dir, 1);
    var host = platform.Host.init(io, .{ .env = .{}, .system_managers = false });
    for ([_][]const u8{ "..\\outside", "C:relative", "C:outside/../bin/tool" }) |target| {
        var output: std.Io.Writer.Allocating = .init(a);
        fixture.reference = try content.writeTar(a, io, .{ .entries = &.{
            .{ .path = "bin/tool", .body = .bytes("value") },
            .{ .path = "link", .kind = .symlink, .link_target = target },
        } }, &output.writer, .{});
        fixture.tar = output.written();
        try std.testing.expectError(
            error.ProgramPath,
            kernel.run(try fixture.options(&host, .install)),
        );
        const cas = try std.fs.path.join(a, &.{ fixture.roots[0].path, ".niobium-v2/cas" });
        try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().openDir(io, cas, .{}));
    }
}
