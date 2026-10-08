//! Cross-platform CGO launcher accepts a build-graph-owned static library path.
const std = @import("std");
const stream_limit = 1 << 20;
pub fn main(init: std.process.Init) !void {
    const tracing = @import("builtin").target.os.tag == .windows and
        std.mem.eql(u8, init.environ_map.get("GITHUB_ACTIONS") orelse "", "true");
    return execute(init, tracing);
}

/// The explicit tracing argument lets launcher tests exercise diagnostics on any host.
pub fn execute(init: std.process.Init, tracing: bool) !void {
    const arena = init.arena.allocator();
    diagnostic(tracing, "entered", .{});
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
    diagnostic(tracing, "configured: argc={d}", .{argv.len});
    const result = std.process.run(arena, init.io, .{
        .argv = argv,
        .environ_map = init.environ_map,
        .stdout_limit = .limited(stream_limit),
        .stderr_limit = .limited(stream_limit),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(300), .clock = .awake } },
    }) catch |err| {
        std.log.err("Go invocation failed: {s}", .{@errorName(err)});
        return err;
    };
    if (tracing and !result.term.success()) {
        retainStderr(init.io, result.stderr) catch |err| {
            std.log.err("Go stderr retention failed: {s}", .{@errorName(err)});
        };
    }
    diagnostic(tracing, "child returned: term={any}, stdout={d}, stderr={d}", .{
        result.term, result.stdout.len, result.stderr.len,
    });
    forward(.stderr(), init.io, result.stderr) catch |err| {
        std.log.err("Go stderr forwarding failed: {s}", .{@errorName(err)});
        return err;
    };
    diagnostic(tracing, "stderr forwarded", .{});
    forward(.stdout(), init.io, result.stdout) catch |err| {
        std.log.err("Go stdout forwarding failed: {s}", .{@errorName(err)});
        return err;
    };
    diagnostic(tracing, "streams forwarded", .{});
    if (!result.term.success()) {
        std.log.err("Go command failed: {any}", .{result.term});
        return error.GoFailed;
    }
    diagnostic(tracing, "complete", .{});
}

fn diagnostic(enabled: bool, comptime format: []const u8, args: anytype) void {
    if (enabled) std.log.info("go-author-build: " ++ format, args);
}

/// Preserve the complete bounded stream while making early diagnostics observable promptly.
fn forward(file: std.Io.File, io: std.Io, bytes: []const u8) std.Io.File.Writer.Error!void {
    std.debug.assert(bytes.len <= stream_limit);
    var offset: usize = 0;
    for (0..128) |_| {
        if (offset == bytes.len) return;
        const end = @min(offset + 8192, bytes.len);
        try file.writeStreamingAll(io, bytes[offset..end]);
        offset = end;
    }
    std.debug.assert(offset == bytes.len);
}

/// The CI invokes this helper from apps/starlark and uploads this evidence directory on failure.
fn retainStderr(io: std.Io, bytes: []const u8) !void {
    std.debug.assert(bytes.len <= stream_limit);
    const directory = "../../.evidence/core-ci";
    try std.Io.Dir.cwd().createDirPath(io, directory);
    var nonce: [16]u8 = undefined; // SAFETY: random initializes the complete suffix.
    io.random(&nonce);
    var storage: [128]u8 = undefined; // SAFETY: bufPrint initializes the returned path.
    const path = try std.fmt.bufPrint(&storage, directory ++ "/go-stderr-{s}.log", .{
        std.fmt.bytesToHex(nonce, .lower),
    });
    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .exclusive = true });
    defer file.close(io);
    try file.writePositionalAll(io, bytes, 0);
}
