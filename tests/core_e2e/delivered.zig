//! Target-side qualification of transferred final bytes. Source provenance comes from the producer.
const std = @import("std");
const program = @import("program");
const provenance = @import("suite_provenance");
const scenarios = @import("main.zig");
const commands = @import("commands.zig");
const Dir = std.Io.Dir;
const build_host = @tagName(@import("builtin").cpu.arch) ++ "-" ++
    @tagName(@import("builtin").os.tag);

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var run = try provenance.Run.startForSuite(arena, init.io, args, "core-delivered");
    execute(&run, args) catch |err| {
        try run.finish(@errorName(err));
        return err;
    };
    try run.finish(null);
    std.log.info("N2-CROSS-02 target execution PASS: {s}", .{run.evidence});
}

fn execute(run: *provenance.Run, args: []const []const u8) !void {
    if (args.len != 2) return error.Usage;
    const own = try std.process.executablePathAlloc(run.io, run.arena);
    const executable = try Dir.cwd().readFileAlloc(run.io, own, run.arena, .limited(30 << 20));
    run.report.executable_sha256 = try program.digest(run.arena, executable);
    const directory = try Dir.cwd().realPathFileAlloc(run.io, args[1], run.arena);
    const files = try run.arena.print("{s}/files.setup", .{directory});
    const first = try run.arena.print("{s}/tools-v1.setup", .{directory});
    const second = try run.arena.print("{s}/tools-v2.setup", .{directory});
    const incompatible = try run.arena.print("{s}/tools-invalid.setup", .{directory});
    const files_image = try scenarios.checkImage(run, files);
    const tools_image = try scenarios.checkImage(run, first);
    try std.testing.expectEqualSlices(
        u8,
        &files_image.template_sha256,
        &tools_image.template_sha256,
    );
    try scenarios.filesLifecycle(run, files);
    try scenarios.toolchainLifecycle(run, first, second, incompatible);
    try commands.record(run, "summary", .{
        .id = "N2-CROSS-02",
        .status = "PASS",
        .source_provenance = "External producer ledger; this witness does not need a checkout",
        .target = build_host,
        .template_sha256 = std.fmt.bytesToHex(files_image.template_sha256, .lower),
    });
}
