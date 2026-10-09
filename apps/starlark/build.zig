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
    if (args.len < 4 or args.len > 32) return error.Usage;
    if (args[1].len > 4096 or std.mem.indexOfAny(u8, args[1], "\"\r\n") != null)
        return error.InvalidLibraryPath;
    if (args[2].len == 0 or args[2].len > 4096) return error.Usage;
    const directory = std.fs.path.dirname(args[1]) orelse return error.InvalidLibraryPath;
    const path = try std.mem.replaceOwned(u8, arena, directory, "\\", "/");
    const flags = try arena.print("\"-L{s}\"", .{path});
    try init.environ_map.put("CGO_LDFLAGS", flags);
    try init.environ_map.put("CGO_ENABLED", "1");
    try init.environ_map.put("GOPROXY", "https://proxy.golang.org,direct");
    try init.environ_map.put("GOTOOLCHAIN", "local");
    try prependGo(arena, init.io, init.environ_map, args[2]);
    const argv = try arena.alloc([]const u8, args.len - 2);
    argv[0] = args[2];
    @memcpy(argv[1..], args[3..]);
    diagnostic(tracing, "configured: argc={d}", .{argv.len});
    const result = std.process.run(arena, init.io, .{
        .argv = argv,
        .environ_map = init.environ_map,
        .stdout_limit = .limited(stream_limit),
        .stderr_limit = .limited(stream_limit),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(900), .clock = .awake } },
    }) catch |err| {
        std.log.err("Go invocation failed: {s}", .{@errorName(err)});
        return err;
    };
    if (tracing and !result.term.success()) {
        retainFailure(init.io, args[1], result.stderr) catch |err| {
            std.log.err("Go diagnostic retention failed: {s}", .{@errorName(err)});
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

fn prependGo(
    arena: std.mem.Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
    go_bin: []const u8,
) !void {
    const bin = std.fs.path.dirname(go_bin) orelse return error.Usage;
    const relative = std.fs.path.dirname(bin) orelse return error.Usage;
    // Go looks up pkg/tool from GOROOT. A relative value keeps `..` in the tool
    // path, which Windows CreateProcess does not resolve.
    const cwd = try std.process.currentPathAlloc(io, arena);
    const goroot = if (std.fs.path.isAbsolute(relative))
        relative
    else
        try std.fs.path.resolveAlloc(arena, &.{ cwd, relative });
    const path_bin = if (std.fs.path.isAbsolute(bin))
        bin
    else
        try std.fs.path.resolveAlloc(arena, &.{ cwd, bin });
    try env.put("GOROOT", goroot);
    const old = env.get("PATH") orelse "";
    const sep: u8 = if (@import("builtin").os.tag == .windows) ';' else ':';
    try env.put("PATH", try std.fmt.allocPrint(arena, "{s}{c}{s}", .{ path_bin, sep, old }));
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

/// CI uploads stderr and the exact failing archive from this build-owned working directory.
fn retainFailure(io: std.Io, archive_path: []const u8, bytes: []const u8) !void {
    std.debug.assert(bytes.len <= stream_limit);
    const directory = "../../.evidence/core-ci";
    try std.Io.Dir.cwd().createDirPath(io, directory);
    var nonce: [16]u8 = undefined; // SAFETY: random initializes the complete suffix.
    io.random(&nonce);
    var storage: [128]u8 = undefined; // SAFETY: bufPrint initializes the returned prefix.
    const prefix = try std.fmt.bufPrint(&storage, directory ++ "/go-stderr-{s}", .{
        std.fmt.bytesToHex(nonce, .lower),
    });
    try retainBytes(io, prefix, ".log", bytes);
    const archive = try retainArchive(io, prefix, archive_path);
    var stderr_digest: [32]u8 = undefined; // SAFETY: hash fills the digest.
    std.crypto.hash.sha2.Sha256.hash(bytes, &stderr_digest, .{});
    const stderr_hex = std.fmt.bytesToHex(stderr_digest, .lower);
    const archive_text: []const u8 = &archive.sha256;
    const stderr_text: []const u8 = &stderr_hex;
    var json: [512]u8 = undefined; // SAFETY: the fixed writer exposes only written bytes.
    var writer: std.Io.Writer = .fixed(&json);
    try std.json.Stringify.value(.{
        .schema = 1,
        .archive = .{ .bytes = archive.bytes, .sha256 = archive_text },
        .stderr_bytes = bytes.len,
        .stderr_sha256 = stderr_text,
    }, .{}, &writer);
    try retainBytes(io, prefix, ".json", writer.buffered());
}

fn retainBytes(io: std.Io, prefix: []const u8, suffix: []const u8, bytes: []const u8) !void {
    var storage: [160]u8 = undefined; // SAFETY: bufPrint initializes the returned path.
    const path = try std.fmt.bufPrint(&storage, "{s}{s}", .{ prefix, suffix });
    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .exclusive = true });
    defer file.close(io);
    try file.writePositionalAll(io, bytes, 0);
}

const Archive = struct { bytes: u64, sha256: [64]u8 };
fn retainArchive(io: std.Io, prefix: []const u8, source_path: []const u8) !Archive {
    const source = try std.Io.Dir.cwd().openFile(io, source_path, .{});
    defer source.close(io);
    const stat = try source.stat(io);
    if (stat.kind != .file or stat.size > 64 << 20) return error.AuthorArchiveLimit;
    var path_storage: [160]u8 = undefined; // SAFETY: bufPrint initializes the path.
    const path = try std.fmt.bufPrint(&path_storage, "{s}.abi.lib", .{prefix});
    const destination = try std.Io.Dir.cwd().createFile(io, path, .{ .exclusive = true });
    defer destination.close(io);
    var scratch: [64 << 10]u8 = undefined; // SAFETY: readPositionalAll fills each hashed slice.
    var hash: std.crypto.hash.sha2.Sha256 = .init(.{});
    var offset: u64 = 0;
    for (0..1024) |_| {
        if (offset == stat.size) break;
        const amount = std.math.cast(usize, @min(stat.size - offset, scratch.len)) orelse
            return error.AuthorArchiveLimit;
        if (try source.readPositionalAll(io, scratch[0..amount], offset) != amount)
            return error.AuthorArchiveChanged;
        hash.update(scratch[0..amount]);
        try destination.writePositionalAll(io, scratch[0..amount], offset);
        offset += amount;
    }
    if (offset != stat.size or (try source.stat(io)).size != stat.size)
        return error.AuthorArchiveChanged;
    return .{ .bytes = stat.size, .sha256 = std.fmt.bytesToHex(hash.finalResult(), .lower) };
}
