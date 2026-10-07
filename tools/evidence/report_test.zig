const std = @import("std");
const model = @import("model.zig");
const store = @import("store.zig");
const records = @import("records.zig");

fn report() model.Report {
    return .{
        .schema = 1,
        .provenance = null,
        .suite = .unit,
        .execution = "fixture",
        .lane = "L1/L2",
        .driver = "fixture",
        .os = "linux",
        .cpu = "x86_64",
        .environment = "isolated",
        .revision = "0000000000000000000000000000000000000000",
        .dirty = true,
        .repository = "example/project",
        .run = "1",
        .attempt = "1",
        .job = "linux",
        .toolchain = "test",
        .target = "x86_64-linux",
        .parameters = &.{ "", "seeds=1", "seed-start=0", "tsan=false", "coverage=false" },
        .started_ms = 1,
        .finished_ms = 2,
        .complete = true,
        .verdict = .PASS,
        .reason = "",
        .cases = &.{},
        .attachments = &.{},
    };
}

test "N1-AC-20 malformed, missing, changed and partial evidence is never a pass" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realPathFileAlloc(io, ".", a);
    var value = report();
    try store.save(a, io, path, value);
    try std.testing.expectError(error.MissingEvidence, store.load(a, io, path));
    for ([_][]const u8{ "stdout.txt", "stderr.txt" }) |file| {
        try tmp.dir.writeFile(io, .{ .sub_path = file, .data = "output" });
    }
    try store.collect(a, io, path, &value);
    try store.save(a, io, path, value);
    const saved = try store.load(a, io, path);
    try std.testing.expectEqual(model.Verdict.PASS, saved.verdict);
    try tmp.dir.writeFile(io, .{ .sub_path = "stdout.txt", .data = "edited" });
    try std.testing.expectError(error.EvidenceDigestMismatch, store.load(a, io, path));
    value.complete = false;
    try std.testing.expectError(error.InvalidReport, model.validate(value));
    value.verdict = .FAIL;
    value.reason = "Timeout";
    try model.validate(value);
    value.suite = .e2e;
    value.lane = "L4";
    value.complete = true;
    value.verdict = .PASS;
    value.reason = "";
    try std.testing.expectError(error.MissingCaseEvidence, model.validate(value));
    try std.testing.expectError(
        error.FileNotFound,
        records.atomicWrite(a, io, try std.fs.path.join(a, &.{ path, "missing", "report" }), "x"),
    );
}

test "N1-AC-20 optional unsupported contracts cannot hide required failures" {
    var value = report();
    value.suite = .conformance;
    value.lane = "L3";
    value.parameters = &.{ "host-user", "seeds=1", "seed-start=0", "tsan=false", "coverage=false" };
    // SAFETY: loop fills all entries.
    var cases: [model.catalog.contracts.len]model.Case = undefined;
    for (model.catalog.contracts, &cases) |contract, *case| case.* = .{
        .id = "host-user",
        .contract = contract,
        .acceptance = &.{"N1-AC-14"},
        .scope = "user",
        .verdict = .PASS,
        .reason = "",
        .started_ms = 1,
        .finished_ms = 2,
    };
    value.cases = &cases;
    cases[6].verdict = .NOT_RUN;
    cases[6].reason = "OptionalCapabilityUnsupported";
    try model.validate(value);
    cases[0].verdict = .NOT_RUN;
    cases[0].reason = "OptionalCapabilityUnsupported";
    try std.testing.expectError(error.InvalidReport, model.validate(value));
}

test "N1-AC-20 report replay parameters and timestamps are checked" {
    var value = report();
    value.started_ms = -1;
    try std.testing.expectError(error.InvalidReport, model.validate(value));
    value.started_ms = 1;
    value.parameters = &.{ "", "seeds=0", "seed-start=0", "tsan=false", "coverage=false" };
    try std.testing.expectError(error.InvalidReport, model.validate(value));
    value.parameters = &.{ "", "seeds=1", "seed-start=0", "tsan=maybe", "coverage=false" };
    try std.testing.expectError(error.InvalidReport, model.validate(value));
}
