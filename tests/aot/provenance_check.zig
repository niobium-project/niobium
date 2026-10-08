//! The executable suite must retain provenance even when its argument contract fails.

const std = @import("std");
const Dir = std.Io.Dir;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) return error.Usage;
    const result = try std.process.run(arena, init.io, .{
        .argv = &.{args[1]},
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(64 << 10),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } },
    });
    if (result.term != .exited or result.term.exited != 1) return error.ExpectedFailure;
    const marker = "evidence ";
    const start = (std.mem.find(u8, result.stderr, marker) orelse
        return error.MissingFailureMetadata) + marker.len;
    const end = std.mem.findScalarPos(u8, result.stderr, start, '\n') orelse result.stderr.len;
    const path = try std.fs.path.join(arena, &.{ result.stderr[start..end], "metadata.json" });
    const bytes = try Dir.cwd().readFileAlloc(init.io, path, arena, .limited(4 << 20));
    const value = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
    const report = value.object;
    if (!std.mem.eql(u8, report.get("status").?.string, "FAIL")) return error.InvalidMetadata;
    if (!std.mem.eql(u8, report.get("failure").?.string, "Usage")) return error.InvalidMetadata;
    if (report.get("exit_code").?.integer != 1) return error.InvalidMetadata;
    if (report.get("finished_ms").?.integer < report.get("started_ms").?.integer) {
        return error.InvalidMetadata;
    }
    if (report.get("revision").?.string.len < 40) return error.InvalidMetadata;
    if (report.get("source_identity_sha256").?.string.len != 64) return error.InvalidMetadata;
    if (report.get("source_files").?.array.items.len == 0) return error.InvalidMetadata;
    if (report.get("dirty").? != .bool) return error.InvalidMetadata;
    const identity = try std.json.Stringify.valueAlloc(arena, .{
        .revision = report.get("revision").?.string,
        .status = report.get("git_status_sha256").?.string,
        .files = report.get("source_files").?,
    }, .{});
    try verifyHash(identity, report.get("source_identity_sha256").?.string);
    var found_source = false;
    for (report.get("source_files").?.array.items) |file| {
        if (!std.mem.eql(u8, file.object.get("path").?.string, "tests/aot/main.zig")) continue;
        const source = try Dir.cwd().readFileAlloc(
            init.io,
            "tests/aot/main.zig",
            arena,
            .limited(8 << 20),
        );
        try verifyHash(source, file.object.get("sha256").?.string);
        found_source = true;
    }
    if (!found_source) return error.InvalidMetadata;

    if (!std.mem.eql(u8, report.get("target").?.string, "aarch64-macos")) {
        return error.InvalidMetadata;
    }
    if (!std.mem.eql(u8, report.get("argv").?.array.items[0].string, args[1])) {
        return error.InvalidMetadata;
    }
}

fn verifyHash(bytes: []const u8, expected: []const u8) !void {
    var hash: [32]u8 = undefined; // SAFETY: hash fills the digest.
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    if (!std.mem.eql(u8, &std.fmt.bytesToHex(hash, .lower), expected)) {
        return error.InvalidMetadata;
    }
}
