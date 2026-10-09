//! N2 component qualification runs every guest in a bounded, disposable worker.
const std = @import("std");
const provenance = @import("suite_provenance");
const Dir = std.Io.Dir;
const Case = struct {
    argv: []const []const u8,
    status: []const u8,
    term: std.process.Child.Term,
    started_ms: i64,
    finished_ms: i64,
    guest_sha256: []const u8,
    log: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);
    var run = try provenance.Run.startForSuite(arena, init.io, argv, "component");
    execute(&run, argv) catch |err| {
        try run.finish(@errorName(err));
        std.log.err("Component qualification failed: {s}; evidence {s}", .{
            @errorName(err), run.evidence,
        });
        return err;
    };
    try run.finish(null);
    std.log.info("Component qualification evidence: {s}", .{run.evidence});
}

fn execute(run: *provenance.Run, argv: []const []const u8) !void {
    try run.capture();
    if (argv.len != 13) return error.Usage;
    {
        const build_log = try Dir.cwd().readFileAlloc(
            run.io,
            argv[12],
            run.arena,
            .limited(64 << 10),
        );
        try Dir.cwd().writeFile(run.io, .{
            .sub_path = try std.fs.path.join(run.arena, &.{ run.evidence, "wit-bindgen.log" }),
            .data = build_log,
        });
    }
    const worker = try Dir.cwd().readFileAlloc(run.io, argv[1], run.arena, .limited(30 << 20));
    var records: std.ArrayList(Case) = .empty;
    const checks = [_]struct { name: []const u8, rejection: ?[]const u8 }{
        .{ .name = "typed", .rejection = null },
        .{ .name = "fuel", .rejection = null },
        .{ .name = "memory", .rejection = null },
        .{ .name = "host-calls", .rejection = null },
        .{ .name = "output", .rejection = "OutputLimit" },
        .{ .name = "type-limit", .rejection = "ResourceLimit" },
        .{ .name = "amplification", .rejection = "NIOBIUM_COMPONENT_ALLOCATION_LIMIT" },
    };
    for (argv[2..4]) |guest| {
        for (checks) |check| {
            try executeCase(run, &records, worker, argv[1], guest, check.name, check.rejection);
        }
    }
    const expected = [_][]const u8{
        "AutomaticInitialization", "UnauthorizedImport", "UnauthorizedImport",
        "threads must be enabled", "memory",
    };
    for (argv[4..9], expected) |guest, rejection| {
        try executeCase(run, &records, worker, argv[1], guest, "instantiate", rejection);
    }
    for (argv[9..11]) |guest| {
        try executeCase(run, &records, worker, argv[1], guest, "type-limit", "ResourceLimit");
    }
    try executeCase(run, &records, worker, argv[1], argv[11], "depth-limit", "ResourceLimit");
}

fn executeCase(
    run: *provenance.Run,
    records: *std.ArrayList(Case),
    worker: []const u8,
    executable: []const u8,
    guest: []const u8,
    action: []const u8,
    rejection: ?[]const u8,
) !void {
    std.debug.assert(records.items.len < 32);
    const argv = try run.arena.dupe([]const u8, &.{ executable, guest, action });
    const started = std.Io.Clock.real.now(run.io).toMilliseconds();
    const result = try std.process.run(run.arena, run.io, .{
        .argv = argv,
        .stdout_limit = .limited(64 << 10),
        .stderr_limit = .limited(64 << 10),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } },
    });
    const log = try std.mem.concat(run.arena, u8, &.{ result.stdout, result.stderr });
    const passed = if (rejection) |needle|
        !result.term.success() and std.mem.indexOf(u8, log, needle) != null
    else
        result.term.success() and std.mem.startsWith(u8, result.stdout, "PASS ");
    const log_name = try run.arena.print("{d}-{s}.log", .{ records.items.len, action });
    try Dir.cwd().writeFile(run.io, .{
        .sub_path = try std.fs.path.join(run.arena, &.{ run.evidence, log_name }),
        .data = log,
    });
    const bytes = try Dir.cwd().readFileAlloc(run.io, guest, run.arena, .limited(4 << 20));
    try records.append(run.arena, .{
        .argv = argv,
        .status = if (passed) "PASS" else "FAIL",
        .term = result.term,
        .started_ms = started,
        .finished_ms = std.Io.Clock.real.now(run.io).toMilliseconds(),
        .guest_sha256 = try digest(run.arena, bytes),
        .log = log_name,
    });
    const report = try std.json.Stringify.valueAlloc(run.arena, .{
        .schema = 1,
        .suite = "component",
        .worker_sha256 = try digest(run.arena, worker),
        .worker_bytes = worker.len,
        .cases = records.items,
    }, .{});
    try Dir.cwd().writeFile(run.io, .{
        .sub_path = try std.fs.path.join(run.arena, &.{ run.evidence, "cases.json" }),
        .data = report,
    });
    if (!passed) return error.ComponentQualification;
}

fn digest(arena: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    return arena.dupe(u8, &std.fmt.bytesToHex(hash, .lower));
}
