//! Native file/directory link projection and cleanup, including explicit context refusal.
const std = @import("std");
const content = @import("content");
const kernel = @import("kernel");
const platform = @import("platform");
const Fixture = @import("fixture.zig").Fixture;
const io = std.testing.io;

test "N2-KERNEL-21: resolved directory links have native kind and unlink without following" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var output: std.Io.Writer.Allocating = .init(arena.allocator());
    fixture.reference = try content.writeTar(arena.allocator(), io, .{ .entries = &.{
        .{ .path = "directory/data", .body = .bytes("nested") },
        .{ .path = "original", .body = .bytes("file") },
        .{ .path = "dir-link", .kind = .symlink, .link_target = "directory" },
        .{ .path = "file-link", .kind = .symlink, .link_target = "original" },
    } }, &output.writer, .{});
    fixture.tar = output.written();
    var host: platform.Host = .init(io, .{ .env = .{} });
    const installed = kernel.run(try fixture.options(&host, .install)) catch |err| {
        if (@import("builtin").os.tag != .windows or err != error.KernelUnsupported) return err;
        std.debug.print("Native directory-link context: unsupported before publication\n", .{});
        var options = try fixture.options(&host, .recover);
        options.model = null;
        const recovered = try kernel.run(options);
        try std.testing.expect(recovered.state == null);
        return;
    };
    const state = installed.state.?;
    std.debug.print("Native directory-link context: created and verified\n", .{});
    try std.testing.expect(state.roots[0].resources[0].link_directory);
    const base = try std.fs.path.join(arena.allocator(), &.{ fixture.roots[0].path, "current" });
    const via_directory = try std.Io.Dir.cwd().readFileAlloc(
        io,
        try std.fs.path.join(
            arena.allocator(),
            &.{
                base, "dir-link", "data",
            },
        ),
        arena.allocator(),
        .limited(
            64,
        ),
    );
    try std.testing.expectEqualStrings("nested", via_directory);
    const via_file = try std.Io.Dir.cwd().readFileAlloc(
        io,
        try std.fs.path.join(
            arena.allocator(),
            &.{
                base, "file-link",
            },
        ),
        arena.allocator(),
        .limited(
            64,
        ),
    );
    try std.testing.expectEqualStrings("file", via_file);
    const removed = try kernel.run(try fixture.options(&host, .uninstall));
    try std.testing.expect(removed.state == null);
    const generation = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path, ".niobium-v2", "generations", state.roots[0].generation,
        },
    );
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, generation, .{}));
}
