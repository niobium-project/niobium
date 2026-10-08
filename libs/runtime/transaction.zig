//! A frozen plan and one durable commit marker select rollback or roll-forward. Guest code is
//! never part of recovery: outputs and state already exist in the plan before the first effect.

const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const storage = @import("storage.zig");
const state = @import("state.zig");

pub const Error = storage.Error || state.Error || error{GenerationConflict};
pub const Checkpoint = struct {
    context: ?*anyopaque = null,
    call: ?*const fn (?*anyopaque, []const u8) void = null,

    pub fn reach(self: Checkpoint, name: []const u8) void {
        if (self.call) |callback| callback(self.context, name);
    }
};

pub fn apply(
    store: storage.Storage,
    owner: state.Owner,
    plan: state.Plan,
    hook: Checkpoint,
) Error!void {
    try state.validatePlan(store.arena, plan, owner, store.path);
    if (plan.next != null and try store.exists(try generationPath(store, plan.generation))) {
        return error.GenerationConflict;
    }
    try store.write("pending.json", try state.encode(store.arena, plan));
    hook.reach("planned");
    try stage(store, plan);
    hook.reach("staged");
    try store.pointer(if (plan.next) |next| next.generation else null);
    hook.reach("swapped");
    try store.write("committed", "commit-v1\n");
    hook.reach("committed");
    try finish(store, plan);
    hook.reach("finalized");
}

pub fn recover(store: storage.Storage, owner: state.Owner) Error!bool {
    const bytes = try store.read("pending.json", (contracts.Limits{}).runtime_plan_bytes) orelse {
        // Marker removal follows plan removal; the remaining marker describes completed work.
        try store.remove("committed");
        return false;
    };
    const plan = try state.decode(state.Plan, store.arena, bytes);
    try state.validatePlan(store.arena, plan, owner, store.path);
    if (try store.read("committed", 64)) |marker| {
        if (!std.mem.eql(u8, marker, "commit-v1\n")) return error.StateInvalid;
        try stage(store, plan);
        try store.pointer(if (plan.next) |next| next.generation else null);
        try finish(store, plan);
    } else {
        if (plan.previous) |old| try verifyGeneration(store, old);
        try store.pointer(if (plan.previous) |old| old.generation else null);
        try writeSnapshot(store, plan.previous);
        if (plan.next) |next| try cleanGeneration(store, next);
        try store.remove("pending.json");
    }
    return true;
}

fn verifyGeneration(store: storage.Storage, snapshot: state.Snapshot) Error!void {
    const base = try generationPath(store, snapshot.generation);
    const receipt_path = try store.arena.print("{s}/.niobium-generation", .{base});
    const bytes = try store.read(receipt_path, (contracts.Limits{}).runtime_plan_bytes) orelse
        return error.StateInvalid;
    const receipt = try state.decode(state.Snapshot, store.arena, bytes);
    const expected = try state.encode(store.arena, snapshot);
    if (!std.mem.eql(u8, expected, try state.encode(store.arena, receipt))) {
        return error.StateInvalid;
    }
    for (snapshot.resources) |resource| {
        const path = try store.arena.print("{s}/{s}", .{ base, resource.path });
        const content = try store.read(path, (contracts.Limits{}).program_blob_bytes) orelse
            return error.StateInvalid;
        if (!std.mem.eql(u8, try program.digest(store.arena, content), resource.sha256)) {
            return error.StateInvalid;
        }
    }
}

fn stage(store: storage.Storage, plan: state.Plan) Error!void {
    const snapshot = plan.next orelse return;
    try reserveGeneration(store, snapshot);
    for (plan.files) |file| {
        const path = try store.arena.print("generations/{d}/{s}", .{ plan.generation, file.path });
        try store.write(path, try program.decodeHex(store.arena, file.data_hex));
    }
}

fn reserveGeneration(store: storage.Storage, snapshot: state.Snapshot) Error!void {
    const base = try generationPath(store, snapshot.generation);
    const receipt = try store.arena.print("{s}/.niobium-generation", .{base});
    const expected = try state.encode(store.arena, snapshot);
    if (try store.read(receipt, (contracts.Limits{}).runtime_plan_bytes)) |bytes| {
        const existing = try state.decode(state.Snapshot, store.arena, bytes);
        if (!std.mem.eql(u8, expected, try state.encode(store.arena, existing))) {
            return error.GenerationConflict;
        }
        return;
    }
    if (!try store.createExclusiveDir(base)) return error.GenerationConflict;
    // Ownership is durable before any resource bytes are written into this generation.
    try store.write(receipt, expected);
}

fn finish(store: storage.Storage, plan: state.Plan) Error!void {
    try writeSnapshot(store, plan.next);
    if (plan.previous) |old| {
        try cleanGeneration(store, old);
    }
    // Deleting the plan first makes a crash here a completed transaction with a stale marker.
    try store.remove("pending.json");
    try store.remove("committed");
}

fn generationPath(store: storage.Storage, generation: u64) Error![]const u8 {
    return store.arena.print("generations/{d}", .{generation});
}

fn cleanGeneration(store: storage.Storage, snapshot: state.Snapshot) Error!void {
    const base = try generationPath(store, snapshot.generation);
    const receipt_path = try store.arena.print("{s}/.niobium-generation", .{base});
    const bytes = try store.read(receipt_path, (contracts.Limits{}).runtime_plan_bytes) orelse {
        // A crash before the ownership receipt cannot have written resource files.
        try store.removeEmpty(base);
        return;
    };
    const receipt = try state.decode(state.Snapshot, store.arena, bytes);
    const expected = try state.encode(store.arena, snapshot);
    if (!std.mem.eql(u8, expected, try state.encode(store.arena, receipt))) {
        return error.StateInvalid;
    }
    for (snapshot.resources) |resource| {
        const path = try store.arena.print("{s}/{s}", .{ base, resource.path });
        try store.remove(path);
        var directory = std.fs.path.dirname(path);
        for (0..(contracts.Limits{}).path_components) |_| {
            const current = directory orelse break;
            if (current.len <= base.len) break;
            try store.removeEmpty(current);
            directory = std.fs.path.dirname(current);
        }
    }
    try store.remove(receipt_path);
    try store.removeEmpty(base);
}

fn writeSnapshot(store: storage.Storage, snapshot: ?state.Snapshot) Error!void {
    if (snapshot) |value| {
        try store.write("installation.json", try state.encode(store.arena, value));
    } else try store.remove("installation.json");
}
