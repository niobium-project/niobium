//! A complete runtime template; product assembly never compiles or links this file.

const std = @import("std");
const builtin = @import("builtin");
const image = @import("image");
const section = if (builtin.target.os.tag == .macos) "__DATA,__nbproduct" else ".nbprod";
pub export var niobium_product_slot: [image.descriptor.size]u8 linksection(section) =
    image.templateSlot();

pub fn main(init: std.process.Init) !void {
    std.mem.doNotOptimizeAway(&niobium_product_slot);
    const arena = init.arena.allocator();
    const own = try std.process.executablePathAlloc(init.io, arena);
    const file = try std.Io.Dir.cwd().openFile(init.io, own, .{});
    defer file.close(init.io);
    const source: image.Source = .{ .file = .{
        .handle = file,
        .length = (try file.stat(init.io)).size,
    } };
    const descriptor = try image.verify(arena, init.io, source, .{});
    var message: [128]u8 = undefined; // SAFETY: positional read fills the printed program bytes.
    const length = std.math.cast(usize, descriptor.program.length) orelse return error.ProgramLimit;
    if (length > message.len) return error.ProgramLimit;
    try source.read(init.io, descriptor.program.offset, message[0..length]);
    try std.Io.File.stdout().writeStreamingAll(init.io, message[0..length]);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
