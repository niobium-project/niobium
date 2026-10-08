//! Real independent-reader regression: preserve link type and exact readlink spelling.

const std = @import("std");
const content = @import("content");

test "N2-CONTENT-05 native tar preserves canonical modes and symbolic links" {
    var allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer allocator.deinit();
    const arena = allocator.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const source: content.Source = .{ .bytes = @embedFile("fixtures/gnu-pax.tar") };
    const tree = try content.parseTar(arena, io, source, .{});
    var encoded: std.Io.Writer.Allocating = .init(arena);
    const identity = try content.writeTar(arena, io, tree, &encoded.writer, .{});
    try temporary.dir.writeFile(io, .{ .sub_path = "input.tar", .data = encoded.written() });
    try temporary.dir.createDir(io, "output", .default_dir);
    const path = try temporary.dir.realPathFileAlloc(io, ".", arena);
    const result = try std.process.run(arena, io, .{
        .argv = &.{ "/usr/bin/tar", "-xf", "input.tar", "-C", "output" },
        .cwd = .{ .path = path },
        .stdout_limit = .limited(64 << 10),
        .stderr_limit = .limited(64 << 10),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(15), .clock = .awake } },
    });
    if (!result.term.success()) {
        std.log.err("tar extraction failed: {s}", .{result.stderr});
        return error.IndependentReaderFailed;
    }
    try verify(arena, io, temporary.dir);
    try std.testing.expectEqual(@as(u64, 11264), identity.bytes);
}

fn verify(arena: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) !void {
    var link: [1024]u8 = undefined; // SAFETY: readLink initializes the returned slice.
    const length = try dir.readLink(io, "output/bin/alias", &link);
    try std.testing.expectEqualStrings("./tool", link[0..length]);
    const bytes = try dir.readFileAlloc(io, "output/bin/tool", arena, .limited(64));
    try std.testing.expectEqualStrings("#!/bin/sh\nexit 0\n", bytes);
    const empty = try dir.openDir(io, "output/empty", .{});
    empty.close(io);
    const file = try dir.openFile(io, "output/bin/tool", .{});
    defer file.close(io);
    const permissions = (try file.stat(io)).permissions;
    try std.testing.expect(permissions.toMode() & 0o111 == 0o111);
}
