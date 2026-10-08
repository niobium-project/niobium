//! Real process termination at coordinator durability boundaries, followed by guest-free recovery.
const std = @import("std");
const kernel = @import("kernel");
const provenance = @import("suite_provenance");
const Dir = std.Io.Dir;
const Point = struct { name: []const u8, root: []const u8 = "", new: bool = false };
const points = [_]Point{
    .{ .name = "planned" },
    .{ .name = "resource-written", .root = "root-0" },
    .{ .name = "root-prepared", .root = "root-0" },
    .{ .name = "resource-written", .root = "root-1" },
    .{ .name = "root-prepared", .root = "root-1" },
    .{ .name = "decision", .new = true },
    .{ .name = "root-activated", .root = "root-0", .new = true },
    .{ .name = "root-activated", .root = "root-1", .new = true },
    .{ .name = "state-written", .new = true },
    .{ .name = "cleaned", .new = true },
    .{ .name = "finalized", .new = true },
};

pub fn main(init: std.process.Init) !void {
    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    var record = try provenance.Run.startForSuite(init.arena.allocator(), init.io, argv, "kernel");
    execute(&record, argv) catch |err| {
        try record.finish(@errorName(err));
        return err;
    };
    try record.finish(null);
    std.log.info("N2-KERNEL-RECOVERY-01 PASS: {s}", .{record.evidence});
}

fn execute(record: *provenance.Run, argv: []const []const u8) !void {
    if (argv.len != 2) return error.Usage;
    try record.capture();
    const driver = try Dir.cwd().realPathFileAlloc(record.io, argv[1], record.arena);
    var results: std.ArrayList(struct { point: Point, status: []const u8 }) = .empty;
    for (points, 0..) |point, index| {
        try killPoint(record, driver, point, index);
        try results.append(record.arena, .{ .point = point, .status = "PASS" });
    }
    for ([_][]const u8{ "current.next", "current.old" }) |name| {
        try rejectForeignPointer(record, driver, name);
    }
    try write(
        record,
        record.evidence,
        "summary",
        .{
            .id = "N2-KERNEL-RECOVERY-01",
            .status = "PASS",
            .cases = results.items,
            .guest_free_recovery = true,
            .reserved_pointer_rejections = 2,
            .simultaneous_visibility = false,
            .windows_native = "NOT_RUN",
            .linux_native = "NOT_RUN",
        },
    );
}

fn killPoint(record: *provenance.Run, driver: []const u8, point: Point, index: usize) !void {
    const directory = try record.arena.print("{s}/case-{d}", .{ record.evidence, index });
    try Dir.cwd().createDir(record.io, directory, .default_dir);
    const first = try command(record, directory, "install", &.{ driver, "install", directory });
    if (!first.term.success()) return error.InstallFailed;
    const killed = try command(
        record,
        directory,
        "kill",
        &.{ driver, "update", directory, point.name, point.root },
    );
    try terminated(killed.term);
    const recovered = try command(
        record,
        directory,
        "recover",
        &.{
            driver, "recover", directory,
        },
    );
    if (!recovered.term.success()) return error.RecoveryFailed;
    const result = try std.json.parseFromSliceLeaky(
        kernel.Result,
        record.arena,
        recovered.stdout,
        .{},
    );
    try witness(record, directory, point, result.state orelse return error.MissingState);
    const state_path = try record.arena.print(
        "{s}/root-0/.niobium-v2/installation.json",
        .{
            directory,
        },
    );
    const before = try Dir.cwd().readFileAlloc(
        record.io,
        state_path,
        record.arena,
        .limited(
            1 << 20,
        ),
    );
    const repeated = try command(
        record,
        directory,
        "repeat",
        &.{
            driver, "recover", directory,
        },
    );
    if (!repeated.term.success()) return error.RecoveryFailed;
    const after = try Dir.cwd().readFileAlloc(
        record.io,
        state_path,
        record.arena,
        .limited(
            1 << 20,
        ),
    );
    if (!std.mem.eql(u8, before, after)) return error.RecoveryChangedState;
}

fn rejectForeignPointer(record: *provenance.Run, driver: []const u8, name: []const u8) !void {
    const directory = try record.arena.print("{s}/foreign-{s}", .{ record.evidence, name });
    try Dir.cwd().createDir(record.io, directory, .default_dir);
    const installed = try command(record, directory, "install", &.{ driver, "install", directory });
    if (!installed.term.success()) return error.InstallFailed;
    const killed = try command(record, directory, "kill", &.{
        driver, "update", directory, "decision", "",
    });
    try terminated(killed.term);
    const sentinel = try record.arena.print("{s}/root-1/{s}", .{ directory, name });
    try Dir.cwd().writeFile(record.io, .{ .sub_path = sentinel, .data = "unowned" });
    const rejected = try command(record, directory, "reject", &.{ driver, "recover", directory });
    if (rejected.term.success() or std.mem.find(u8, rejected.stderr, "KernelDrift") == null) {
        return error.ForeignPointerAccepted;
    }
    const retained = try Dir.cwd().readFileAlloc(record.io, sentinel, record.arena, .limited(64));
    if (!std.mem.eql(u8, retained, "unowned")) return error.ForeignPointerChanged;
    const old = try std.json.parseFromSliceLeaky(
        kernel.Result,
        record.arena,
        installed.stdout,
        .{},
    );
    try witness(record, directory, .{ .name = "foreign-rejection" }, old.state.?);
    try Dir.cwd().deleteFile(record.io, sentinel);
    const recovered = try command(record, directory, "recover", &.{ driver, "recover", directory });
    if (!recovered.term.success()) return error.RecoveryFailed;
    const next = try std.json.parseFromSliceLeaky(
        kernel.Result,
        record.arena,
        recovered.stdout,
        .{},
    );
    try witness(record, directory, .{ .name = "foreign-recovered", .new = true }, next.state.?);
}

fn witness(
    record: *provenance.Run,
    directory: []const u8,
    point: Point,
    state: kernel.Snapshot,
) !void {
    const expected_version: u32 = if (point.new) 2 else 1;
    const expected_text = if (point.new) "second" else "first";
    if (state.release_sequence != expected_version or state.calls.len != 1 or
        state.calls[0].version != expected_version or state.roots.len != 2) return error.MixedState;
    if (state.migrations.len != (if (point.new) @as(usize, 1) else 0)) return error.MixedState;
    for (state.roots) |root| {
        const path = try record.arena.print("{s}/{s}/current/bin/tool", .{ directory, root.id });
        const bytes = try Dir.cwd().readFileAlloc(record.io, path, record.arena, .limited(64));
        if (!std.mem.eql(u8, expected_text, bytes)) return error.MixedFiles;
        const link = try record.arena.print("{s}/{s}/current", .{ directory, root.id });
        var target: [1024]u8 = undefined; // SAFETY: readLink fills the returned prefix.
        const length = try Dir.cwd().readLink(record.io, link, &target);
        const expected = try record.arena.print(
            ".niobium-v2/generations/{s}/data",
            .{
                root.generation,
            },
        );
        const root_path = try record.arena.print("{s}/{s}", .{ directory, root.id });
        const actual_path = try std.fs.path.resolve(
            record.arena,
            &.{
                root_path, target[0..length],
            },
        );
        const expected_path = try std.fs.path.resolve(record.arena, &.{ root_path, expected });
        if (!std.mem.eql(u8, actual_path, expected_path)) return error.MixedGeneration;
    }
}

fn terminated(term: std.process.Child.Term) !void {
    if (@import("builtin").os.tag == .windows) {
        switch (term) {
            .exited => |status| if (status != 137) return error.ExpectedTermination,
            else => return error.ExpectedTermination,
        }
    } else switch (term) {
        .signal => |signal| if (@backingInt(signal) != 9) return error.ExpectedSigkill,
        else => return error.ExpectedSigkill,
    }
}

fn command(
    record: *provenance.Run,
    dir: []const u8,
    label: []const u8,
    argv: []const []const u8,
) !std.process.RunResult {
    const result = try std.process.run(
        record.arena,
        record.io,
        .{
            .argv = argv,
            .stdout_limit = .limited(1 << 20),
            .stderr_limit = .limited(1 << 20),
            .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } },
        },
    );
    try write(
        record,
        dir,
        label,
        .{
            .argv = argv,
            .term = result.term,
            .stdout = result.stdout,
            .stderr = result.stderr,
        },
    );
    return result;
}

fn write(record: *provenance.Run, dir: []const u8, label: []const u8, value: anytype) !void {
    const path = try record.arena.print("{s}/{s}.json", .{ dir, label });
    try Dir.cwd().writeFile(
        record.io,
        .{
            .sub_path = path,
            .data = try std.json.Stringify.valueAlloc(record.arena, value, .{}),
        },
    );
}
