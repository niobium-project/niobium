//! Normalize independent tar implementations' output through the public content API.

const std = @import("std");
const content = @import("content");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.Usage;
    const input = try std.Io.Dir.cwd().openFile(init.io, args[1], .{});
    defer input.close(init.io);
    const source: content.Source = .{ .file = .{
        .handle = input,
        .length = (try input.stat(init.io)).size,
    } };
    const tree = try content.parseTar(init.arena.allocator(), init.io, source, .{});
    const output = try std.Io.Dir.cwd().createFile(init.io, args[2], .{});
    defer output.close(init.io);
    var buffer: [64 << 10]u8 = undefined;
    var writer = output.writer(init.io, &buffer);
    const reference = try content.writeTar(
        init.arena.allocator(),
        init.io,
        tree,
        &writer.interface,
        .{},
    );
    try writer.interface.flush();
    try output.sync(init.io);
    const digest = std.fmt.bytesToHex(reference.sha256, .lower);
    try std.Io.File.stdout().writeStreamingAll(init.io, &digest);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
