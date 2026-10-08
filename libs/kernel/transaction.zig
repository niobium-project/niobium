//! Durable coordinator decision precedes every root activation. Recovery never invokes guests.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const platform = @import("platform");
const t = @import("types.zig");
const wire = @import("wire.zig");
const storage = @import("storage.zig");
const ownership = @import("ownership.zig");
const containers = @import("containers.zig");
const generation = @import("generation.zig");
const cleanup = @import("cleanup.zig");
const Error = t.Error;
const pending = storage.metadata ++ "/pending.json";
const decision = storage.metadata ++ "/decision";
const snapshot_path = storage.metadata ++ "/installation.json";

pub fn current(session: ownership.Session) Error!?t.Snapshot {
    const store = session.stateStore();
    const bytes = try store.read(snapshot_path, contracts.limits.default.runtime_plan_bytes) orelse
        return null;
    const value = try wire.decode(t.Snapshot, store.arena, bytes);
    try wire.snapshot(store.arena, value, session.owner);
    return value;
}

pub fn apply(session: ownership.Session, plan: t.Plan, inventory: containers.Inventory) Error!void {
    try wire.plan(session.options.arena, plan, session.owner);
    try pointers(session, plan.previous, null, false);
    const store = session.stateStore();
    const bytes = try wire.encode(store.arena, plan);
    const hash = try program.digest(store.arena, bytes);
    if (plan.next) |next| for (next.roots) |root| {
        const target = try session.store(root.id);
        if (try target.exists(try generation.base(store.arena, root.generation))) {
            return error.KernelConflict;
        }
    };
    try store.write(pending, bytes);
    session.options.checkpoint.reach("planned", null);
    if (plan.next) |next| for (next.roots) |root| {
        try generation.prepare(
            try session.store(root.id),
            root,
            try inventory.root(root.id),
            hash,
            session.options.checkpoint,
        );
    };
    try store.write(decision, hash);
    session.options.checkpoint.reach("decision", null);
    try finish(session, plan, hash);
}

pub fn recover(session: ownership.Session) Error!bool {
    const store = session.stateStore();
    const bytes = try store.read(pending, contracts.limits.default.runtime_plan_bytes) orelse {
        if (try store.read(decision, 64)) |marker| {
            try wire.hash(marker);
            try store.remove(decision);
        }
        return false;
    };
    const plan = try wire.decode(t.Plan, store.arena, bytes);
    try wire.plan(session.options.arena, plan, session.owner);
    const hash = try program.digest(store.arena, bytes);
    if (try store.read(decision, 64)) |marker| {
        if (!std.mem.eql(u8, marker, hash)) return error.KernelPlan;
        try pointers(session, plan.previous, plan.next, true);
        try finish(session, plan, hash);
    } else {
        try pointers(session, plan.previous, null, false);
        if (plan.next) |next| for (next.roots) |root| {
            try cleanup.aborted(try session.store(root.id), root, hash);
        };
        try snapshot(store, plan.previous);
        try store.remove(pending);
    }
    return true;
}

fn finish(session: ownership.Session, plan: t.Plan, hash: []const u8) Error!void {
    // Authenticate every prepared root before activating any further root.
    if (plan.next) |next| for (next.roots) |root| {
        const store = try session.store(root.id);
        const receipt = try generation.prepared(store, root, hash);
        std.debug.assert(receipt.schema == 2);
        if (!try pointsAt(store, root.generation)) try generation.verify(store, root, hash, true);
    };
    for (session.stores) |store| {
        const next = if (plan.next) |value| program.find(
            t.RootState,
            value.roots,
            store.binding.id,
        ) else null;
        try activate(session.options.platform, store, if (next) |value| value.generation else null);
        session.options.checkpoint.reach("root-activated", store.binding.id);
    }
    try snapshot(session.stateStore(), plan.next);
    session.options.checkpoint.reach("state-written", null);
    if (plan.previous) |prior| for (prior.roots) |root| {
        try cleanup.retired(try session.store(root.id), root);
    };
    session.options.checkpoint.reach("cleaned", null);
    try session.stateStore().remove(pending);
    try session.stateStore().remove(decision);
    session.options.checkpoint.reach("finalized", null);
}

fn snapshot(store: storage.Store, value: ?t.Snapshot) Error!void {
    if (value) |next| {
        try store.write(snapshot_path, try wire.encode(store.arena, next));
    } else try store.remove(snapshot_path);
}

fn activate(host: platform.Platform, store: storage.Store, next: ?[]const u8) Error!void {
    const link = try std.fs.path.join(store.arena, &.{ store.binding.path, "current" });
    if (next) |value| {
        if (try pointsAt(store, value)) return;
        const target = try store.arena.print(
            "{s}/data",
            .{
                try generation.base(
                    store.arena,
                    value,
                ),
            },
        );
        try host.setPointer(link, target);
    } else try host.deletePointer(link);
    try storage.sync(store.io, store.dir);
}

fn pointers(
    session: ownership.Session,
    previous: ?t.Snapshot,
    next: ?t.Snapshot,
    committed: bool,
) Error!void {
    try auxiliaryPointers(session, previous, next, committed);
    for (session.stores) |store| {
        const old = if (previous) |state| program.find(
            t.RootState,
            state.roots,
            store.binding.id,
        ) else null;
        const new = if (next) |state| program.find(
            t.RootState,
            state.roots,
            store.binding.id,
        ) else null;
        const actual = try pointer(store);
        if (old) |value| {
            if (try equals(store, actual, value.generation)) continue;
        } else if (actual == null) continue;
        if (new) |value| {
            if (try equals(store, actual, value.generation)) continue;
            // A Windows junction replacement can be interrupted after unlinking old.
            if (@import("builtin").os.tag == .windows and actual == null) continue;
        } else if (committed and actual == null) continue;
        return error.KernelDrift;
    }
}

fn auxiliaryPointers(
    session: ownership.Session,
    previous: ?t.Snapshot,
    next: ?t.Snapshot,
    committed: bool,
) Error!void {
    for (session.stores) |store| {
        for ([_][]const u8{ "current.next", "current.old" }) |name| {
            if (!try store.exists(name)) continue;
            if (!committed) return error.KernelConflict;
            const link = try std.fs.path.join(store.arena, &.{ store.binding.path, name });
            const actual = platform.local.readPointer(store.io, store.arena, link) catch
                return error.KernelDrift;
            if (previous) |state| {
                const prior = program.find(t.RootState, state.roots, store.binding.id) orelse
                    return error.KernelPlan;
                if (try equals(store, actual, prior.generation)) continue;
            }
            if (next) |state| {
                const desired = program.find(t.RootState, state.roots, store.binding.id) orelse
                    return error.KernelPlan;
                if (try equals(store, actual, desired.generation)) continue;
            }
            return error.KernelDrift;
        }
    }
}

pub fn pointsAt(store: storage.Store, value: []const u8) Error!bool {
    return equals(store, try pointer(store), value);
}

fn pointer(store: storage.Store) Error!?[]const u8 {
    const link = try std.fs.path.join(store.arena, &.{ store.binding.path, "current" });
    return platform.local.readPointer(store.io, store.arena, link);
}

fn equals(store: storage.Store, actual: ?[]const u8, value: []const u8) Error!bool {
    const text = actual orelse return false;
    const relative = try store.arena.print("{s}/data", .{try generation.base(store.arena, value)});
    if (std.mem.eql(u8, text, relative)) return true;
    const expected = try std.fs.path.resolve(store.arena, &.{ store.binding.path, relative });
    const resolved = try std.fs.path.resolve(store.arena, &.{ store.binding.path, text });
    return std.mem.eql(u8, expected, resolved);
}
