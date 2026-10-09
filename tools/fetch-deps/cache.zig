//! Shared download cache for third-party sources and host toolchains.
//! Bytes live at `<cache>/<sha256>` (ADR-0011). A mismatch is never retried.

const std = @import("std");
const builtin = @import("builtin");

const Dir = std.Io.Dir;

pub fn defaultCache(arena: std.mem.Allocator, environ: *const std.process.Environ.Map) ![]const u8 {
    if (environ.get("NIOBIUM_DEPS_CACHE")) |dir| return dir;
    const zig_cache = environ.get("ZIG_GLOBAL_CACHE_DIR") orelse if (builtin.os.tag == .windows)
        try std.fs.path.join(arena, &.{
            environ.get("LOCALAPPDATA") orelse return error.FetchNoCacheDir,
            "zig",
        })
    else if (environ.get("XDG_CACHE_HOME")) |xdg|
        try std.fs.path.join(arena, &.{ xdg, "zig" })
    else
        try std.fs.path.join(arena, &.{
            environ.get("HOME") orelse return error.FetchNoCacheDir,
            ".cache",
            "zig",
        });
    return std.fs.path.join(arena, &.{ zig_cache, "niobium-deps" });
}

/// Verified bytes of `url`: from `cache_path/<sha256>` when present, else downloaded.
pub fn obtain(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    cache_path: []const u8,
    url: []const u8,
    sha256: []const u8,
    max: u64,
) ![]const u8 {
    std.debug.assert(sha256.len == 64);
    std.debug.assert(max != 0);
    var cache = try Dir.cwd().createDirPathOpen(io, cache_path, .{});
    defer cache.close(io);
    if (cache.readFileAlloc(io, sha256, arena, .limited64(max))) |bytes| {
        if (matches(bytes, sha256)) return bytes;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
    try downloadFile(io, gpa, arena, environ, cache, sha256, url, max);
    const bytes = try cache.readFileAlloc(io, sha256, arena, .limited64(max));
    if (!matches(bytes, sha256)) return error.FetchHashMismatch;
    return bytes;
}

pub fn matches(bytes: []const u8, expected_hex: []const u8) bool {
    var digest: [32]u8 = undefined; // SAFETY: hash writes the full digest.
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return std.mem.eql(u8, &hex, expected_hex);
}

pub fn boundedBody(reader: *std.Io.Reader, arena: std.mem.Allocator, max: u64) ![]u8 {
    const bytes = reader.allocRemaining(arena, .limited64(max + 1)) catch |err| switch (err) {
        error.StreamTooLong => return error.FetchTooLarge,
        else => return err,
    };
    if (bytes.len > max) return error.FetchTooLarge;
    return bytes;
}

fn downloadFile(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    cache: Dir,
    sha256: []const u8,
    url: []const u8,
    max: u64,
) !void {
    const partial = try std.fmt.allocPrint(arena, "{s}.partial", .{sha256});
    var delay_seconds: i64 = 2;
    for (0..8) |_| {
        const start = fileSize(io, cache, partial);
        pull(io, gpa, arena, environ, cache, partial, url, max, start) catch |err| {
            if (err == error.FetchTooLarge) return err;
            std.debug.print("fetch-deps: {s}: {s}, retrying\n", .{ url, @errorName(err) });
            try io.sleep(.fromSeconds(delay_seconds), .awake);
            delay_seconds *= 2;
            continue;
        };
        if (!try hashFile(io, gpa, cache, partial, sha256, max)) {
            cache.deleteFile(io, partial) catch |delete_error| switch (delete_error) {
                error.FileNotFound => {},
                else => return delete_error,
            };
            return error.FetchHashMismatch;
        }
        try Dir.rename(cache, partial, cache, sha256, io);
        return;
    }
    return error.FetchHttpStatus;
}

fn fileSize(io: std.Io, cache: Dir, path: []const u8) u64 {
    const stat = cache.statFile(io, path, .{}) catch return 0;
    return stat.size;
}

fn pull(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    cache: Dir,
    partial: []const u8,
    url: []const u8,
    max: u64,
    start: u64,
) !void {
    var client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer client.deinit();
    try client.initDefaultProxies(arena, environ);
    var range_buf: [80]u8 = undefined; // SAFETY: bufPrint returns the initialized prefix.
    const range = try std.fmt.bufPrint(&range_buf, "bytes={d}-", .{start});
    const extra: []const std.http.Header = if (start == 0)
        &.{}
    else
        &.{.{ .name = "range", .value = range }};
    const uri = try std.Uri.parse(url);
    var request = try client.request(.GET, uri, .{
        .redirect_behavior = .init(3),
        .extra_headers = extra,
        .headers = .{ .accept_encoding = .{ .override = "identity" } },
    });
    defer request.deinit();
    try request.sendBodiless();
    var redirect: [8 << 10]u8 = undefined; // SAFETY: response header scratch.
    var response = try request.receiveHead(&redirect);
    const resumed = response.head.status == .partial_content;
    if (response.head.status != .ok and !resumed) return error.FetchHttpStatus;
    const declared = response.head.content_length;
    if (declared) |length| {
        const total = if (resumed) start + length else length;
        if (total > max) return error.FetchTooLarge;
    }
    var file = try cache.createFile(io, partial, .{ .truncate = !resumed });
    defer file.close(io);
    const base: u64 = if (resumed) start else 0;
    var transfer: [64 << 10]u8 = undefined; // SAFETY: body reader scratch.
    var reader = response.reader(&transfer);
    var got: u64 = 0;
    var chunk: [64 << 10]u8 = undefined; // SAFETY: readSliceShort fills the returned prefix.
    // loop-bound: each iteration consumes at least one byte and stops at content-length or max.
    while (base + got <= max) {
        if (declared) |limit| if (got >= limit) break;
        if (base + got > max) return error.FetchTooLarge;
        const n = reader.readSliceShort(&chunk) catch return error.HttpRequestTruncated;
        if (n == 0) break;
        try file.writePositionalAll(io, chunk[0..n], base + got);
        got += n;
    }
    if (declared) |limit| if (got != limit) return error.HttpRequestTruncated;
}

fn hashFile(
    io: std.Io,
    gpa: std.mem.Allocator,
    cache: Dir,
    path: []const u8,
    expected: []const u8,
    max: u64,
) !bool {
    const bytes = try cache.readFileAlloc(io, path, gpa, .limited64(max));
    defer gpa.free(bytes);
    return matches(bytes, expected);
}
