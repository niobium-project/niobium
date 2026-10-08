//! Independent POSIX pax producers must converge on the same logical identity.

const std = @import("std");
const content = @import("content");

test "N2-CONTENT-05 GNU tar and libarchive archives normalize identically" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var previous: ?[]const u8 = null;
    for ([_][]const u8{
        @embedFile("fixtures/gnu-pax.tar"),
        @embedFile("fixtures/libarchive-pax.tar"),
    }) |input| {
        const tree = try content.parseTar(a, std.testing.io, .{ .bytes = input }, .{});
        var output: std.Io.Writer.Allocating = .init(a);
        const result = try content.writeTar(a, std.testing.io, tree, &output.writer, .{});
        const hex = std.fmt.bytesToHex(result.sha256, .lower);
        try std.testing.expectEqualStrings(
            "e52575e52af743e4860ccfdfa3517d336b52b1fd3f749af93bcdf9ce32cd4b80",
            &hex,
        );
        if (previous) |bytes| try std.testing.expectEqualSlices(u8, bytes, output.written());
        previous = output.written();
        try std.testing.expectEqual(@as(usize, 6), tree.entries.len);
        try std.testing.expectEqualStrings("./tool", tree.entries[1].link_target);
        try std.testing.expectEqual(@as(u16, 0o755), tree.entries[2].mode);
    }
}

test "N2-CONTENT-02 bounded tar parser fuzz corpus" {
    try std.testing.fuzz({}, fuzzContent, .{ .corpus = &.{
        "",
        @embedFile("fixtures/gnu-pax.tar"),
        @embedFile("fixtures/libarchive-pax.tar"),
    } });
}

fn fuzzContent(_: void, smith: *std.testing.Smith) !void {
    var input: [32 << 10]u8 = @splat(0);
    const length = smith.slice(&input);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const parsed = content.parseTar(arena.allocator(), std.testing.io, .{
        .bytes = input[0..length],
    }, .{ .files_per_artifact = 128, .expanded_bytes = 32 << 10 });
    if (parsed) |tree| {
        try std.testing.expect(tree.entries.len <= 128);
        var scratch: [4096]u8 = undefined; // SAFETY: the discard sink only writes this buffer.
        var sink: std.Io.Writer.Discarding = .init(&scratch);
        const result = try content.writeTar(
            arena.allocator(),
            std.testing.io,
            tree,
            &sink.writer,
            .{},
        );
        try std.testing.expect(result.bytes % 512 == 0);
    } else |err| switch (err) {
        error.OutOfMemory => return err,
        else => return,
    }
}
