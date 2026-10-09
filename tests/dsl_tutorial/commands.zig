//! Bound and record each real tutorial command, preserving argument boundaries.
const std = @import("std");
const program = @import("program");
const compiler = @import("compiler");
const provenance = @import("suite_provenance");
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
    const binary = try Dir.cwd().readFileAlloc(
        run.io,
        argv[0],
        run.arena,
        .limited((@import("contracts").Limits{}).test_attachment_bytes),
    );
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

pub fn success(
    run: *provenance.Run,
    name: []const u8,
    argv: []const []const u8,
) ![]const u8 {
    const result = try execute(run, name, argv);
    if (!result.term.success()) {
        std.log.err("{s}: {s}", .{ name, result.stderr });
        return error.CommandFailed;
    }
    return result.stdout;
}

pub fn compileArgs(
    run: *provenance.Run,
    executable: []const u8,
    directory: []const u8,
    name: []const u8,
) ![]const []const u8 {
    const a = run.arena;
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(
        a,
        &.{
            executable,
            "compile",
            "--program",
            try a.print("{s}/{s}.program.json", .{ directory, name }),
            "--source-map",
            try a.print("{s}/{s}.sources.json", .{ directory, name }),
            "--lock",
            try a.print("{s}/inputs.lock.json", .{directory}),
            "--runtime",
            "runtime",
            "--runtime-metadata",
            "runtime-metadata",
            "--worker",
            "worker",
            "--output",
            try a.print("{s}/{s}.setup", .{ directory, name }),
        },
    );
    const bytes = try Dir.cwd().readFileAlloc(
        run.io,
        try a.print("{s}/inputs.lock.json", .{directory}),
        a,
        .limited(1 << 20),
    );
    const lock = try compiler.lock.decode(a, bytes);
    for (lock.inputs) |input| {
        try argv.appendSlice(
            a,
            &.{ "--input", try a.print("{s}={s}/{s}", .{ input.id, directory, input.id }) },
        );
        if (std.mem.eql(u8, input.id, "signer"))
            try argv.appendSlice(a, &.{ "--signer", "signer" });
    }
    return argv.items;
}

pub fn action(
    run: *provenance.Run,
    setup: []const u8,
    root: []const u8,
    verb: []const u8,
    extra: []const []const u8,
    name: []const u8,
) ![]const u8 {
    return success(run, name, try std.mem.concat(run.arena, []const u8, &.{
        &.{ setup, verb, "--root", try run.arena.print("application={s}", .{root}) }, extra,
    }));
}

pub fn record(run: *provenance.Run, name: []const u8, value: anytype) !void {
    const path = try run.arena.print("{s}/{s}.json", .{ run.evidence, name });
    const bytes = try std.json.Stringify.valueAlloc(run.arena, value, .{});
    const file = try Dir.cwd().createFile(run.io, path, .{ .exclusive = true });
    defer file.close(run.io);
    try file.writeStreamingAll(run.io, bytes);
    try file.sync(run.io);
}
