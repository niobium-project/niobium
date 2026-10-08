//! Guest evaluation produces a frozen host plan. This phase never mutates the installation.

const std = @import("std");
const builtin = @import("builtin");
const contracts = @import("contracts");
const program = @import("program");
const wasm = @import("wasm_host");
const state = @import("state.zig");

pub const Error = state.Error || wasm.Error || error{
    InputUnknown,
    ReleaseRegression,
    ReleaseIdentityMismatch,
};

pub fn prepare(
    arena: std.mem.Allocator,
    model: program.Program,
    owner: state.Owner,
    root_path: []const u8,
    current: ?state.Snapshot,
    overrides: []const state.Value,
) Error!state.Plan {
    try program.validate(model);
    const program_hash = try program.digest(arena, try program.encode(arena, model));
    if (current) |old| {
        if (model.release_sequence < old.release_sequence) return error.ReleaseRegression;
        if (model.release_sequence == old.release_sequence) {
            if (!std.mem.eql(u8, program_hash, old.program_sha256)) {
                return error.ReleaseIdentityMismatch;
            }
        }
    }
    const inputs = try resolveInputs(arena, model.inputs, current, overrides);
    var migrations: std.ArrayList(state.Migration) = .empty;
    if (current) |old| try migrations.appendSlice(arena, old.migrations);
    if (current) |old| if (try state.transition(
        model.upgrades,
        old.model_version,
        model.model_version,
    )) |rule| try recordMigration(arena, &migrations, rule, "@product", program_hash);
    var files: std.ArrayList(state.File) = .empty;
    var instances: std.ArrayList(state.Instance) = .empty;
    for (model.instances) |instance| {
        try evaluateInstance(arena, .{
            .model = model,
            .instance = instance,
            .inputs = inputs,
            .previous = if (current) |old|
                program.find(state.Instance, old.instances, instance.id)
            else
                null,
        }, &files, &instances, &migrations);
    }
    const generation = if (current) |old|
        std.math.add(u64, old.generation, 1) catch return error.StateInvalid
    else
        1;
    const snapshot: state.Snapshot = .{
        .root_id = owner.root_id,
        .product_id = model.product_id,
        .generation = generation,
        .release_sequence = model.release_sequence,
        .model_version = model.model_version,
        .program_sha256 = program_hash,
        .inputs = inputs,
        .instances = instances.items,
        .migrations = migrations.items,
        .resources = try inventory(arena, files.items),
    };
    return .{
        .root_id = owner.root_id,
        .root_path = root_path,
        .product_id = model.product_id,
        .generation = generation,
        .previous = current,
        .next = snapshot,
        .files = files.items,
    };
}

fn inventory(arena: std.mem.Allocator, files: []const state.File) Error![]const state.Resource {
    const result = try arena.alloc(state.Resource, files.len);
    for (result, files) |*resource, file| {
        resource.* = .{ .id = file.id, .path = file.path, .sha256 = file.sha256 };
    }
    return result;
}

const Invocation = struct {
    model: program.Program,
    instance: program.Instance,
    inputs: []const state.Value,
    previous: ?state.Instance,
};

fn evaluateInstance(
    arena: std.mem.Allocator,
    call: Invocation,
    files: *std.ArrayList(state.File),
    instances: *std.ArrayList(state.Instance),
    migrations: *std.ArrayList(state.Migration),
) Error!void {
    const instance = call.instance;
    const library = program.find(program.Library, call.model.libraries, instance.library) orelse
        return error.ProgramReference;
    const inputs = try arena.alloc([]const u8, instance.inputs.len);
    for (inputs, instance.inputs) |*value, id| {
        const input = program.find(state.Value, call.inputs, id) orelse
            return error.ProgramReference;
        value.* = input.value;
    }
    const assets = try arena.alloc([]const u8, instance.assets.len);
    for (assets, instance.assets) |*value, id| {
        const asset = program.find(program.Asset, call.model.assets, id) orelse
            return error.ProgramReference;
        value.* = try program.decodeHex(arena, asset.data_hex);
    }
    var migration: ?wasm.Migration = null;
    if (call.previous) |old| if (try state.transition(
        instance.migrations,
        old.version,
        instance.state_version,
    )) |rule| {
        migration = .{ .from = rule.from, .to = rule.to };
        try recordMigration(arena, migrations, rule, instance.id, library.sha256);
    };
    const output = try wasm.evaluate(arena, try program.decodeHex(arena, library.wasm_hex), .{
        .inputs = inputs,
        .assets = assets,
        .previous_state = if (call.previous) |old|
            try program.decodeHex(arena, old.data_hex)
        else
            "",
        .os = @tagName(builtin.os.tag),
        .arch = @tagName(builtin.cpu.arch),
        .resource_count = std.math.cast(u32, instance.resources.len) orelse
            return error.ProgramLimit,
    }, migration, .{});
    try collectFiles(arena, call, output.resources, files);
    try instances.append(arena, .{
        .id = instance.id,
        .library_id = library.id,
        .library_sha256 = library.sha256,
        .version = instance.state_version,
        .data_hex = try program.encodeHex(arena, output.state),
    });
}

fn collectFiles(
    arena: std.mem.Allocator,
    call: Invocation,
    outputs: []const wasm.ResourceOutput,
    files: *std.ArrayList(state.File),
) Error!void {
    const instance = call.instance;
    for (outputs) |resource| {
        if (resource.handle >= instance.resources.len) return error.ProgramReference;
        const target = program.find(
            program.Resource,
            call.model.resources,
            instance.resources[resource.handle],
        ) orelse return error.ProgramReference;
        try files.append(arena, .{
            .id = target.id,
            .path = target.path,
            .sha256 = try program.digest(arena, resource.bytes),
            .data_hex = try program.encodeHex(arena, resource.bytes),
        });
    }
}

fn resolveInputs(
    arena: std.mem.Allocator,
    declarations: []const program.Input,
    current: ?state.Snapshot,
    overrides: []const state.Value,
) Error![]const state.Value {
    if (overrides.len > (contracts.Limits{}).program_items) return error.ProgramLimit;
    for (overrides, 0..) |value, index| {
        if (program.find(program.Input, declarations, value.id) == null) return error.InputUnknown;
        if (value.value.len > (contracts.Limits{}).program_state_bytes) return error.ProgramLimit;
        if (program.find(state.Value, overrides[0..index], value.id) != null) {
            return error.ProgramDuplicate;
        }
    }
    const result = try arena.alloc(state.Value, declarations.len);
    for (result, declarations) |*value, declaration| {
        const previous = if (current) |old|
            program.find(state.Value, old.inputs, declaration.id)
        else
            null;
        const explicit = program.find(state.Value, overrides, declaration.id);
        value.* = .{
            .id = declaration.id,
            .value = if (explicit) |v|
                v.value
            else if (previous) |v|
                v.value
            else
                declaration.default,
        };
    }
    return result;
}

fn recordMigration(
    arena: std.mem.Allocator,
    records: *std.ArrayList(state.Migration),
    rule: program.Migration,
    owner: []const u8,
    hash: []const u8,
) Error!void {
    if (records.items.len >= (contracts.Limits{}).program_items) return error.ProgramLimit;
    for (records.items) |old| {
        if (!std.mem.eql(u8, old.owner, owner) or !std.mem.eql(u8, old.id, rule.id)) continue;
        return error.StateInvalid;
    }
    try records.append(arena, .{
        .id = rule.id,
        .owner = owner,
        .from = rule.from,
        .to = rule.to,
        .implementation_sha256 = hash,
    });
}
