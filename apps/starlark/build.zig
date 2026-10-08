//! Cross-platform CGO launcher accepts a build-graph-owned static library path.
const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3 or args.len > 32) return error.Usage;
    if (args[1].len > 4096 or std.mem.indexOfAny(u8, args[1], "\"\r\n") != null)
        return error.InvalidLibraryPath;
    const directory = std.fs.path.dirname(args[1]) orelse return error.InvalidLibraryPath;
    const path = try std.mem.replaceOwned(u8, arena, directory, "\\", "/");
    const flags = try arena.print("\"-L{s}\"", .{path});
    try init.environ_map.put("CGO_LDFLAGS", flags);
    try init.environ_map.put("CGO_ENABLED", "1");
    try init.environ_map.put("GOPROXY", "https://proxy.golang.org,direct");
    const argv = try arena.alloc([]const u8, args.len - 1);
    argv[0] = "go";
    @memcpy(argv[1..], args[2..]);
    const result = try std.process.run(arena, init.io, .{
        .argv = argv,
        .environ_map = init.environ_map,
        .stdout_limit = .limited(1 << 20),
        .stderr_limit = .limited(1 << 20),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(300), .clock = .awake } },
    });
    try std.Io.File.stdout().writeStreamingAll(init.io, result.stdout);
    try std.Io.File.stderr().writeStreamingAll(init.io, result.stderr);
    if (!result.term.success()) return error.GoFailed;
}
