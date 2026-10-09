//! N2-AUTH-02: three public frontends bind identical actual library bytes into normalized IR.
const std = @import("std");
const program = @import("program");
const provenance = @import("suite_provenance");
const Dir = std.Io.Dir;
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var run = try provenance.Run.startForSuite(arena, init.io, args, "author");
    verify(&run, args) catch |err| {
        try run.finish(@errorName(err));
        return err;
    };
    try run.finish(null);
    std.log.info("Author evidence: {s}", .{run.evidence});
}
fn verify(run: *provenance.Run, args: []const []const u8) !void {
    try run.capture();
    if (args.len != 6 and args.len != 7) return error.Usage;
    const bytes = try Dir.cwd().readFileAlloc(run.io, args[5], run.arena, .limited(4 << 20));
    var digest: [32]u8 = undefined; // SAFETY: hash fills the complete array.
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hash = std.fmt.bytesToHex(digest, .lower);
    const length = try run.arena.print("{d}", .{bytes.len});
    const target = if (args.len == 7) args[6] else try currentTarget();
    const sha_arg = try run.arena.print("library_sha256={s}", .{hash});
    const length_arg = try run.arena.print("library_bytes={s}", .{length});
    const target_arg = try run.arena.print("target={s}", .{target});
    var results: [3][]const u8 = undefined; // SAFETY: each slot is filled before comparison.
    for ([_][]const u8{ "native", "c", "starlark" }, 0..) |name, index| {
        const path = try run.arena.print("{s}/{s}.program", .{ run.evidence, name });
        const source_map = try run.arena.print("{s}/starlark.sources.json", .{run.evidence});
        const command: []const []const u8 = if (index < 2)
            &.{ args[index + 1], path, &hash, length, target }
        else
            &.{
                args[3],
                "--source",
                args[4],
                "--out",
                path,
                "--arg",
                sha_arg,
                "--arg",
                length_arg,
                "--arg",
                target_arg,
                "--source-map",
                source_map,
            };
        try execute(run, command, name);
        results[index] = try Dir.cwd().readFileAlloc(run.io, path, run.arena, .limited(1 << 20));
    }
    try std.testing.expectEqualStrings(results[0], results[1]);
    try std.testing.expectEqualStrings(results[0], results[2]);
    const model = try program.model.decode(run.arena, results[0]);
    try std.testing.expectEqualStrings(&hash, model.libraries[0].sha256);
    try std.testing.expectEqual(bytes.len, model.libraries[0].bytes);
    try std.testing.expectEqual(@as(usize, 1), model.calls.len);
    try std.testing.expectEqual(@as(usize, 8), model.calls[0].arguments[0].record.len);
}
fn execute(run: *provenance.Run, argv: []const []const u8, name: []const u8) !void {
    const result = try std.process.run(run.arena, run.io, .{
        .argv = argv,
        .stdout_limit = .limited(64 << 10),
        .stderr_limit = .limited(64 << 10),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } },
    });
    const binary = try Dir.cwd().readFileAlloc(run.io, argv[0], run.arena, .limited(30 << 20));
    var digest: [32]u8 = undefined; // SAFETY: hash fills the complete array.
    std.crypto.hash.sha2.Sha256.hash(binary, &digest, .{});
    const report = try std.json.Stringify.valueAlloc(run.arena, .{
        .argv = argv,
        .executable_sha256 = std.fmt.bytesToHex(digest, .lower),
        .term = result.term,
        .stdout = result.stdout,
        .stderr = result.stderr,
    }, .{});
    try Dir.cwd().writeFile(run.io, .{
        .sub_path = try run.arena.print("{s}/{s}.command.json", .{ run.evidence, name }),
        .data = report,
    });
    if (!result.term.success()) return error.AuthoringFailed;
}

fn currentTarget() error{UnsupportedTarget}![]const u8 {
    const target = @import("builtin").target;
    return switch (target.os.tag) {
        .macos => if (target.cpu.arch == .aarch64) "aarch64-macos" else error.UnsupportedTarget,
        .windows => if (target.cpu.arch == .x86_64) "x86_64-windows" else error.UnsupportedTarget,
        .linux => if (target.cpu.arch == .x86_64) "x86_64-linux" else error.UnsupportedTarget,
        else => error.UnsupportedTarget,
    };
}
