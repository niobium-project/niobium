//! Every process witness records the exact executable and returned bytes.
const std = @import("std");
const provenance = @import("suite_provenance");
const program = @import("program");
const prepare = @import("prepare.zig");
const Dir = std.Io.Dir;

pub fn execute(
    run: *provenance.Run,
    name: []const u8,
    argv: []const []const u8,
) !std.process.RunResult {
    const result = try std.process.run(run.arena, run.io, .{
        .argv = argv,
        .stdout_limit = .limited(16 << 20),
        .stderr_limit = .limited(1 << 20),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(60), .clock = .awake } },
    });
    const binary = try Dir.cwd().readFileAlloc(run.io, argv[0], run.arena, .limited(64 << 20));
    try record(
        run,
        name,
        .{
            .argv = argv,
            .term = result.term,
            .executable_sha256 = try program.digest(run.arena, binary),
            .stdout = result.stdout,
            .stderr = result.stderr,
        },
    );
    return result;
}

pub fn success(run: *provenance.Run, name: []const u8, argv: []const []const u8) ![]const u8 {
    const result = try execute(run, name, argv);
    if (!result.term.success()) {
        std.log.err("{s}: {s}", .{ name, result.stderr });
        return error.CommandFailed;
    }
    return result.stdout;
}

pub fn compile(
    run: *provenance.Run,
    compiler: []const u8,
    prepared: prepare.Prepared,
    name: []const u8,
) ![]const u8 {
    const a = run.arena;
    const output = try a.print("{s}/{s}.setup", .{ prepared.directory, name });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(
        a,
        &.{
            compiler,
            "compile",
            "--program",
            try a.print("{s}/{s}.program.json", .{ prepared.directory, name }),
            "--lock",
            prepared.lock_path,
            "--runtime",
            "runtime",
            "--runtime-metadata",
            "runtime-metadata",
            "--worker",
            "worker",
            "--output",
            output,
        },
    );
    for (prepared.inputs) |input| {
        try argv.appendSlice(
            a,
            &.{ "--input", try a.print("{s}={s}", .{ input.entry.id, input.path }) },
        );
        if (std.mem.eql(u8, input.entry.id, "signer")) try argv.appendSlice(
            a,
            &.{ "--signer", "signer" },
        );
    }
    const result = try success(run, try a.print("compile-{s}", .{name}), argv.items);
    try record(run, try a.print("compile-{s}-result", .{name}), .{ .stdout = result });
    return output;
}

pub fn action(
    run: *provenance.Run,
    setup: []const u8,
    root: []const u8,
    verb: []const u8,
    extra: []const []const u8,
    name: []const u8,
) ![]const u8 {
    const argv = try std.mem.concat(run.arena, []const u8, &.{
        &.{ setup, verb, "--root", try run.arena.print("application={s}", .{root}) }, extra,
    });
    return success(run, name, argv);
}

pub fn record(run: *provenance.Run, name: []const u8, value: anytype) !void {
    const path = try run.arena.print("{s}/{s}.json", .{ run.evidence, name });
    try Dir.cwd().writeFile(
        run.io,
        .{ .sub_path = path, .data = try std.json.Stringify.valueAlloc(run.arena, value, .{}) },
    );
}
