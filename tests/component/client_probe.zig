//! A hostile native child exercises the parent's process boundary independently of the engine.
const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.Usage;
    if (std.mem.eql(u8, args[1], "shape")) {
        return std.Io.File.stdout().writeStreamingAll(
            init.io,
            "{\"schema\":1,\"status\":\"ok\",\"result\":{\"boolean\":true}}\n",
        );
    }
    if (std.mem.eql(u8, args[1], "overflow")) {
        const bytes: [70 << 10]u8 = @splat('x');
        return std.Io.File.stdout().writeStreamingAll(init.io, &bytes);
    }
    if (!std.mem.eql(u8, args[1], "hang") or args.len != 3) return error.Usage;
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = "started" });
    // lint-allow(no-sleep-in-tests): This child sleep is the cancellation/deadline subject.
    try std.Io.sleep(init.io, .fromSeconds(60), .awake);
}
