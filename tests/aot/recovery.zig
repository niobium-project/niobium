//! Actual SIGKILL at durable boundaries, followed by guest-independent recovery.

const std = @import("std");
const runtime = @import("runtime");
const World = @import("world.zig").World;
const expect = @import("world.zig").expect;
const Setups = @import("packaging.zig").Setups;
const lifecycle = @import("lifecycle.zig");

pub fn verify(w: *World, setups: Setups) !void {
    for ([_][]const u8{ "planned", "staged", "swapped", "committed", "finalized" }) |phase| {
        try killedUpgrade(w, setups, phase);
    }
    try unknownPlan(w, setups);
    try w.case("N2-REC-01", "five-kill-points-without-guest", "PASS");
}

fn killedUpgrade(w: *World, setups: Setups, phase: []const u8) !void {
    const root = try w.path(try w.arena.print("kill-{s}", .{phase}));
    try w.command(&.{ setups.v1, "install", "--root", root }, true);
    const before = try w.read(try std.fs.path.join(w.arena, &.{ root, "installation.json" }));
    const candidate = try w.temporary(try w.arena.print("kill-{s}-setup", .{phase}));
    try w.copy(setups.v2, candidate);
    try killAt(w, &.{
        candidate, "apply", "--root", root, "--set", "sdk=next", "--failpoint", phase,
    }, phase);
    // The only executable containing the update's library is unavailable to recovery.
    try w.remove(candidate);
    const recovered = try w.status(w.tools.runtime, root, "recover");
    try expect(recovered.recovered != std.mem.eql(u8, phase, "finalized"));
    const snapshot = recovered.state orelse return error.MissingState;
    const roll_forward = std.mem.eql(u8, phase, "committed") or
        std.mem.eql(u8, phase, "finalized");
    if (roll_forward) {
        try lifecycle.snapshot(w, snapshot, 2, 2, "next", 2);
        try lifecycle.environment(w, root, "next", "2:stable");
    } else {
        try lifecycle.snapshot(w, snapshot, 1, 1, "stable", 0);
        try lifecycle.environment(w, root, "stable", "");
        try w.expectFile(try std.fs.path.join(w.arena, &.{ root, "installation.json" }), before);
    }
    const again = try w.status(w.tools.runtime, root, "recover");
    try expect(!again.recovered);
    const recovered_bytes = try runtime.state.encode(w.arena, recovered.state);
    const repeated_bytes = try runtime.state.encode(w.arena, again.state);
    try expect(std.mem.eql(u8, recovered_bytes, repeated_bytes));
    const abandoned = if (roll_forward) "generations/1" else "generations/2";
    try expect(!try w.exists(try std.fs.path.join(w.arena, &.{ root, abandoned })));
    try w.expectFile(
        try std.fs.path.join(w.arena, &.{ root, "current/.niobium-generation" }),
        recovered_bytes,
    );
    try expect(!try w.exists(try std.fs.path.join(w.arena, &.{ root, "pending.json" })));
    try w.case("N2-REC-01", phase, "PASS");
}

fn unknownPlan(w: *World, setups: Setups) !void {
    const root = try w.path("unknown-plan");
    try w.command(&.{ setups.v1, "install", "--root", root }, true);
    try killAt(w, &.{
        setups.v2, "apply", "--root", root, "--failpoint", "planned",
    }, "unknown-plan");
    const path = try std.fs.path.join(w.arena, &.{ root, "pending.json" });
    const raw = try w.read(path);
    var plan = try runtime.state.decode(runtime.state.Plan, w.arena, raw);
    plan.schema = 99;
    try w.write(path, try runtime.state.encode(w.arena, plan));
    const malformed = try w.read(path);
    const current = try std.fs.path.join(w.arena, &.{ root, "installation.json" });
    const before = try w.read(current);
    try w.command(&.{ w.tools.runtime, "recover", "--root", root }, false);
    try w.expectFile(current, before);
    try w.expectFile(path, malformed);
    try lifecycle.environment(w, root, "stable", "");
    // Restore the known plan and show recovery still succeeds without reevaluating a guest.
    try w.write(path, raw);
    const result = try w.status(w.tools.runtime, root, "recover");
    try expect(result.recovered);
    try w.case("N2-REC-01", "unknown-plan-version-refused", "PASS");
}

fn killAt(w: *World, argv: []const []const u8, phase: []const u8) !void {
    var child = try std.process.spawn(w.io, .{
        .argv = argv,
        .cwd = .{ .path = w.isolated },
        .environ_map = &w.env,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .pipe,
    });
    defer child.kill(w.io);
    var buffer: [4096]u8 = undefined; // SAFETY: reads initialize the retained prefix.
    var used: usize = 0;
    const deadline = (std.Io.Timeout{
        .duration = .{ .raw = .fromSeconds(30), .clock = .awake },
    }).toDeadline(w.io);
    while (used < buffer.len) {
        const result = try w.io.operateTimeout(.{ .file_read_streaming = .{
            .file = child.stderr orelse return error.MissingPipe,
            .data = &.{buffer[used..]},
        } }, deadline);
        const count = try result.file_read_streaming;
        if (count == 0) return error.MissingCheckpoint;
        used += count;
        if (std.mem.indexOf(u8, buffer[0..used], "NIOBIUM_FAILPOINT\n") != null) break;
    }
    try expect(std.mem.indexOf(u8, buffer[0..used], "NIOBIUM_FAILPOINT\n") != null);
    if (std.c.kill(child.id orelse return error.MissingChild, .KILL) != 0) return error.KillFailed;
    const term = try child.wait(w.io);
    try w.record(.{
        .argv = argv,
        .checkpoint = phase,
        .stderr = buffer[0..used],
        .term = term,
    });
    try expect(term == .signal);
    try expect(term.signal == .KILL);
}
