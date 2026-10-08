//! Native execution host for compiled products. Product policy stays in bound Wasm libraries;
//! the host owns validation, resource writes and recovery.

const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
pub const storage = @import("storage.zig");
pub const state = @import("state.zig");
pub const transaction = @import("transaction.zig");
pub const evaluation = @import("evaluate.zig");

pub const Error = evaluation.Error || transaction.Error || error{
    ProductMismatch,
    NotInstalled,
    RootNotEmpty,
};
pub const Action = enum {
    install,
    apply,
    uninstall,
    status,
    recover,

    pub fn needsProduct(action: Action) bool {
        return action != .status and action != .recover;
    }
};
pub const Options = struct {
    io: std.Io,
    arena: std.mem.Allocator,
    root: []const u8,
    action: Action,
    model: ?program.Program = null,
    inputs: []const state.Value = &.{},
    checkpoint: transaction.Checkpoint = .{},
};
pub const Result = struct { recovered: bool, state: ?state.Snapshot };

pub fn run(options: Options) Error!Result {
    if (options.action.needsProduct() and options.model == null) return error.ProductMismatch;
    if (options.model) |model| try program.validate(model);
    const store = try storage.Storage.open(options.io, options.arena, options.root);
    defer store.close();
    const owner = try ownership(store, options.model);
    const recovered = try transaction.recover(store, owner);
    const current = try readState(store, owner);
    if (options.action == .status or options.action == .recover) {
        return .{ .recovered = recovered, .state = current };
    }
    const plan = if (options.action == .uninstall)
        try uninstallPlan(store, owner, current)
    else
        try evaluation.prepare(
            options.arena,
            options.model orelse return error.ProductMismatch,
            owner,
            store.path,
            current,
            options.inputs,
        );
    try state.validatePlan(store.arena, plan, owner, store.path);
    if (try store.read("owner.json", 4096) == null) {
        try store.write("owner.json", try state.encode(store.arena, owner));
    }
    try transaction.apply(store, owner, plan, options.checkpoint);
    return .{ .recovered = recovered, .state = plan.next };
}

fn ownership(store: storage.Storage, model: ?program.Program) Error!state.Owner {
    if (try store.read("owner.json", 4096)) |bytes| {
        const owner = try state.decode(state.Owner, store.arena, bytes);
        if (owner.schema != 1 or owner.root_id.len != 32) return error.StateInvalid;
        try program.validation.identifier(owner.product_id);
        if (model) |value| {
            if (!std.mem.eql(u8, owner.product_id, value.product_id)) return error.ProductMismatch;
        }
        return owner;
    }
    const value = model orelse return error.NotInstalled;
    if (!try store.unclaimedEmpty()) return error.RootNotEmpty;
    var random: [16]u8 = undefined; // SAFETY: random fills every byte.
    store.io.random(&random);
    const owner: state.Owner = .{
        .product_id = value.product_id,
        .root_id = try program.encodeHex(store.arena, &random),
    };
    return owner;
}

fn readState(store: storage.Storage, owner: state.Owner) Error!?state.Snapshot {
    const maybe_bytes = try store.read(
        "installation.json",
        (contracts.Limits{}).runtime_plan_bytes,
    );
    const bytes = maybe_bytes orelse {
        if (try store.readPointer() != null) return error.StateInvalid;
        return null;
    };
    const current = try state.decode(state.Snapshot, store.arena, bytes);
    try state.validateSnapshot(current, owner);
    const target = try store.readPointer() orelse return error.StateInvalid;
    const expected = try store.arena.print("generations/{d}", .{current.generation});
    if (!std.mem.eql(u8, target, expected)) return error.StateInvalid;
    const receipt_path = try store.arena.print("{s}/.niobium-generation", .{expected});
    const maybe_receipt = try store.read(receipt_path, (contracts.Limits{}).runtime_plan_bytes);
    const receipt_bytes = maybe_receipt orelse return error.StateInvalid;
    const receipt = try state.decode(state.Snapshot, store.arena, receipt_bytes);
    try state.validateSnapshot(receipt, owner);
    const current_bytes = try state.encode(store.arena, current);
    if (!std.mem.eql(u8, current_bytes, try state.encode(store.arena, receipt))) {
        return error.StateInvalid;
    }
    return current;
}

fn uninstallPlan(
    store: storage.Storage,
    owner: state.Owner,
    current: ?state.Snapshot,
) Error!state.Plan {
    const previous = current orelse return error.NotInstalled;
    return .{
        .root_id = owner.root_id,
        .root_path = store.path,
        .product_id = owner.product_id,
        .generation = std.math.add(u64, previous.generation, 1) catch return error.StateInvalid,
        .previous = previous,
        .next = null,
        .files = &.{},
    };
}

test {
    _ = @import("runtime_test.zig");
}

test "N2-SAFE-01: mutating actions require a product before opening storage" {
    for ([_]Action{ .install, .apply, .uninstall }) |action| {
        try std.testing.expectError(error.ProductMismatch, run(.{
            .io = std.testing.io,
            .arena = std.testing.allocator,
            .root = "relative-root-must-not-be-opened",
            .action = action,
        }));
    }
}
