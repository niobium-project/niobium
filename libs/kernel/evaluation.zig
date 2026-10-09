//! Compatibility selection and trusted evaluator receipts precede frozen filesystem work.
const std = @import("std");
const program = @import("program");
const contracts = @import("contracts");
const t = @import("types.zig");
const wire = @import("wire.zig");
const Error = t.Error;
pub const Selection = struct {
    inputs: []const t.Input,
    migrations: []const t.Migration,
    model_migration: ?program.Migration,
    program_sha256: []const u8,
};

pub fn select(options: t.Options, current: ?t.Snapshot) Error!Selection {
    const model = options.model orelse return error.KernelInvalid;
    const digest = try program.digest(
        options.arena,
        try program.model.encode(
            options.arena,
            model,
        ),
    );
    var model_migration: ?program.Migration = null;
    var migrations: std.ArrayList(t.Migration) = .empty;
    if (current) |prior| {
        try @import("history.zig").declared(options.arena, model, prior);
        if (options.action == .install) return error.KernelConflict;
        if (model.release_sequence < prior.release_sequence) return error.KernelUpgrade;
        if (model.release_sequence == prior.release_sequence and
            !std.mem.eql(u8, digest, prior.program_sha256)) return error.KernelUpgrade;
        if (options.action != .update and options.action != .uninstall and
            model.release_sequence != prior.release_sequence) return error.KernelUpgrade;
        if (model.model_version != prior.model_version) {
            model_migration = try modelRule(
                model.upgrades,
                prior.model_version,
                model.model_version,
            );
        }
        for (prior.calls) |old| {
            const call = program.find(program.model.Call, model.calls, old.id) orelse continue;
            if (!std.mem.eql(u8, call.library, old.library) or
                !std.mem.eql(u8, call.interface, old.interface) or
                !std.mem.eql(u8, call.function, old.function)) return error.KernelUpgrade;
            if (call.state_version == old.version) continue;
            const rule = try callRule(call, old.version);
            // The current migration ABI consumes a prior value, not an optional value.
            if (old.value == null) return error.KernelUpgrade;
            try migrations.append(options.arena, .{ .call = call.id, .rule = rule });
        }
    } else if (options.action != .install and options.action != .uninstall) {
        return error.KernelState;
    }
    return .{
        .inputs = try inputs(options, model, current),
        .migrations = migrations.items,
        .model_migration = model_migration,
        .program_sha256 = digest,
    };
}

fn modelRule(rules: []const program.Migration, from: u32, to: u32) Error!program.Migration {
    for (rules) |rule| if (rule.from == from and rule.to == to) return rule;
    return error.KernelUpgrade;
}

fn callRule(call: program.model.Call, from: u32) Error!program.model.Migration {
    for (call.migrations) |rule| {
        if (rule.from == from and rule.to == call.state_version) return rule;
    }
    return error.KernelUpgrade;
}

fn inputs(
    options: t.Options,
    model: program.model.Product,
    current: ?t.Snapshot,
) Error![]const t.Input {
    try wire.inputs(options.inputs);
    for (options.inputs) |input| {
        if (program.find(program.model.Input, model.inputs, input.id) == null) {
            return error.KernelInvalid;
        }
    }
    const result = try options.arena.alloc(t.Input, model.inputs.len);
    for (model.inputs, 0..) |input, index| {
        result[index] = .{ .id = input.id, .value = input.default };
        if (current) |prior| {
            if (program.find(t.Input, prior.inputs, input.id)) |existing| {
                result[index].value = existing.value;
            }
        }
        if (program.find(t.Input, options.inputs, input.id)) |override| {
            result[index].value = override.value;
        }
    }
    return result;
}

pub fn receipt(
    arena: std.mem.Allocator,
    model: program.model.Product,
    selected: Selection,
    result: t.EvaluationResult,
) Error![]const t.CallState {
    if (result.containers.len > contracts.limits.default.program_items or
        result.states.len > contracts.limits.default.program_items or
        result.migrations.len > contracts.limits.default.program_items) return error.KernelLimit;
    for (result.migrations) |migration| try wire.migrationValid(migration);
    if (!std.mem.eql(
        u8,
        try wire.encode(arena, selected.migrations),
        try wire.encode(arena, result.migrations),
    )) return error.KernelEvaluation;
    var states: std.ArrayList(t.CallState) = .empty;
    for (result.states, 0..) |state, index| {
        for (result.states[0..index]) |other| {
            if (std.mem.eql(u8, other.call, state.call)) return error.KernelEvaluation;
        }
        const call = program.find(program.model.Call, model.calls, state.call) orelse
            return error.KernelEvaluation;
        if (call.result_role != .plan) return error.KernelEvaluation;
        const library = program.find(program.model.Library, model.libraries, call.library) orelse
            return error.KernelInvalid;
        if (state.value) |value| try program.value.validate(value, .{});
        try states.append(
            arena,
            .{
                .id = call.id,
                .library = call.library,
                .interface = call.interface,
                .function = call.function,
                .implementation_sha256 = library.sha256,
                .version = call.state_version,
                .value = state.value,
            },
        );
    }
    for (model.calls) |call| {
        if (call.result_role != .plan) continue;
        var found = false;
        for (result.states) |state| if (std.mem.eql(u8, state.call, call.id)) {
            found = true;
        };
        if (!found) return error.KernelEvaluation;
    }
    return states.items;
}

pub fn authorize(
    model: program.model.Product,
    desired: t.DesiredContainer,
) Error!program.model.Grant {
    const call = program.find(program.model.Call, model.calls, desired.call) orelse
        return error.KernelEvaluation;
    if (call.result_role != .plan) return error.KernelEvaluation;
    var granted = false;
    for (call.grants) |id| if (std.mem.eql(u8, id, desired.grant)) {
        granted = true;
    };
    if (!granted) return error.ProgramAuthority;
    const grant = program.find(program.model.Grant, model.grants, desired.grant) orelse
        return error.ProgramAuthority;
    if (!std.mem.eql(u8, grant.primitive.id, "content.tree") or grant.primitive.version != 1) {
        return error.ProgramAuthority;
    }
    if (!std.mem.eql(u8, grant.root, desired.root)) return error.ProgramAuthority;
    if (desired.prefix.len > 0) try wire.path(desired.prefix);
    if (!within(grant.prefix, desired.prefix)) return error.ProgramAuthority;
    try ceiling(desired.file_access, grant.file_access);
    try ceiling(desired.directory_access, grant.directory_access);
    return grant;
}

fn ceiling(requested: @import("access").Policy, maximum: @import("access").Policy) Error!void {
    try @import("access").validate(requested);
    if (requested.kind != maximum.kind or requested.owner.bits() & ~maximum.owner.bits() != 0 or
        requested.everyone.bits() & ~maximum.everyone.bits() != 0) return error.ProgramAuthority;
}

pub fn within(parent: []const u8, child: []const u8) bool {
    if (parent.len == 0 or std.mem.eql(u8, parent, child)) return true;
    return child.len > parent.len and std.mem.startsWith(u8, child, parent) and
        child[parent.len] == '/';
}
