//! Validate, evaluate, freeze, prepare, decide, activate. Policy stays in the product graph.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const t = @import("types.zig");
const wire = @import("wire.zig");
const storage = @import("storage.zig");
const ownership = @import("ownership.zig");
const transaction = @import("transaction.zig");
const evaluation = @import("evaluation.zig");
const containers = @import("containers.zig");
const Error = t.Error;

pub fn run(options: t.Options) Error!t.Result {
    try validate(options);
    const session = try ownership.open(options);
    defer session.close();
    const recovered = try transaction.recover(session);
    const current = try transaction.current(session);
    if (!options.action.needsProduct()) return .{ .state = current, .recovered = recovered };
    const selected = try evaluation.select(options, current);
    if (options.action == .uninstall and current == null) {
        return .{ .state = null, .recovered = recovered };
    }
    const id = try storage.nonce(options.arena, options.io);
    var plan: t.Plan = .{
        .instance = session.owner.instance,
        .product_id = session.owner.product_id,
        .transaction = id,
        .roots = session.owner.roots,
        .state_root = session.owner.state_root,
        .previous = current,
        .next = null,
        .containers = &.{},
    };
    var inventory: containers.Inventory = .{ .roots = &.{}, .files = &.{} };
    defer inventory.close(options.io);
    var workspace: ?std.Io.Dir = null;
    defer if (workspace) |directory| directory.close(options.io);
    if (options.action != .uninstall) {
        const work_path = try options.arena.print(storage.metadata ++ "/work/{s}", .{id});
        workspace = try session.stateStore().createDir(work_path);
        const result = try evaluate(session, current, selected, workspace.?);
        const model = options.model orelse return error.KernelInvalid;
        const calls = try evaluation.receipt(options.arena, model, selected, result);
        for (result.containers) |desired| {
            const grant = try evaluation.authorize(model, desired);
            std.debug.assert(grant.max_entries > 0);
        }
        try containers.preflight(session.stateStore(), result.containers, options.content, model);
        try containers.freeze(session.stateStore(), result.containers, options.content);
        inventory = try containers.inventory(
            session.stateStore(),
            session.owner.roots,
            result.containers,
            model,
        );
        plan.containers = result.containers;
        plan.next = try nextState(session, current, selected, id, inventory, calls);
    }
    try transaction.apply(session, plan, inventory);
    return .{ .state = plan.next, .recovered = recovered };
}

fn evaluate(
    session: ownership.Session,
    current: ?t.Snapshot,
    selected: evaluation.Selection,
    workspace: std.Io.Dir,
) Error!t.EvaluationResult {
    const options = session.options;
    const model = options.model orelse return error.KernelInvalid;
    const callback = options.evaluator.call orelse return error.KernelEvaluation;
    return callback(
        options.evaluator.context,
        options.arena,
        options.io,
        .{
            .model = model,
            .current = current,
            .inputs = selected.inputs,
            .action = options.action,
            .selected_migrations = selected.migrations,
            .workspace = workspace,
        },
    );
}

fn nextState(
    session: ownership.Session,
    current: ?t.Snapshot,
    selected: evaluation.Selection,
    id: []const u8,
    inventory: containers.Inventory,
    calls: []const t.CallState,
) Error!t.Snapshot {
    const model = session.options.model orelse return error.KernelInvalid;
    const arena = session.options.arena;
    var migrations: std.ArrayList(t.Migration) = .empty;
    var model_migrations: std.ArrayList(program.Migration) = .empty;
    if (current) |prior| {
        try migrations.appendSlice(arena, prior.migrations);
        try model_migrations.appendSlice(arena, prior.model_migrations);
    }
    try migrations.appendSlice(arena, selected.migrations);
    if (selected.model_migration) |rule| try model_migrations.append(arena, rule);
    if (migrations.items.len > contracts.limits.default.plan_ops or
        model_migrations.items.len > contracts.limits.default.plan_ops) return error.KernelLimit;
    return .{
        .instance = session.owner.instance,
        .product_id = model.id,
        .release_sequence = model.release_sequence,
        .model_version = model.model_version,
        .program_sha256 = selected.program_sha256,
        .inputs = selected.inputs,
        .calls = calls,
        .migrations = migrations.items,
        .model_migrations = model_migrations.items,
        .roots = try containers.states(arena, inventory, id),
    };
}

fn validate(options: t.Options) Error!void {
    try wire.bindings(options.roots, options.state_root);
    try wire.inputs(options.inputs);
    if (options.action.needsProduct() and options.model == null) return error.KernelInvalid;
    if (options.model) |model| {
        try program.model.validate(model);
        try @import("input_validation.zig").defaults(model);
        try @import("input_validation.zig").overrides(options.arena, model, options.inputs);
        const encoded = try program.model.encode(options.arena, model);
        std.debug.assert(encoded.len > 0);
        if (model.roots.len != options.roots.len or
            !std.mem.eql(u8, model.state_root, options.state_root)) return error.KernelInvalid;
        for (model.roots) |root| {
            if (program.find(
                t.RootBinding,
                options.roots,
                root.id,
            ) == null) return error.KernelInvalid;
        }
        const native = @import("builtin").os.tag;
        const target_os: std.Target.Os.Tag = switch (model.target) {
            .@"aarch64-macos" => .macos,
            .@"x86_64-linux" => .linux,
            .@"x86_64-windows" => .windows,
        };
        const target_arch: std.Target.Cpu.Arch = switch (model.target) {
            .@"aarch64-macos" => .aarch64,
            .@"x86_64-linux", .@"x86_64-windows" => .x86_64,
        };
        if (target_os != native or target_arch != @import("builtin").cpu.arch) {
            return error.KernelUnsupported;
        }
    }
}
