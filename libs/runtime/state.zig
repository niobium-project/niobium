//! Durable identities and frozen outputs. No process-local handles enter persisted plans.

const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");

pub const Error = program.Error || error{ StateInvalid, UpgradeUnsupported, PlanUnsupported };
pub const Owner = struct { schema: u32 = 1, product_id: []const u8, root_id: []const u8 };
pub const Value = struct { id: []const u8, value: []const u8 };
pub const Resource = struct { id: []const u8, path: []const u8, sha256: []const u8 };
pub const Instance = struct {
    id: []const u8,
    library_id: []const u8,
    library_sha256: []const u8,
    version: u32,
    data_hex: []const u8,
};
pub const Migration = struct {
    id: []const u8,
    owner: []const u8,
    from: u32,
    to: u32,
    implementation_sha256: []const u8,
};
pub const Snapshot = struct {
    schema: u32 = 1,
    root_id: []const u8,
    product_id: []const u8,
    generation: u64,
    release_sequence: u64,
    model_version: u32,
    program_sha256: []const u8,
    inputs: []const Value,
    instances: []const Instance,
    migrations: []const Migration,
    resources: []const Resource = &.{},
};
pub const File = struct {
    id: []const u8,
    path: []const u8,
    sha256: []const u8,
    data_hex: []const u8,
};
pub const Plan = struct {
    schema: u32 = 1,
    host_abi: u32 = 1,
    root_id: []const u8,
    root_path: []const u8,
    product_id: []const u8,
    generation: u64,
    previous: ?Snapshot,
    next: ?Snapshot,
    files: []const File,
};

pub fn encode(arena: std.mem.Allocator, value: anytype) Error![]const u8 {
    const bytes = try std.json.Stringify.valueAlloc(arena, value, .{});
    if (bytes.len > (contracts.Limits{}).runtime_plan_bytes) return error.ProgramLimit;
    return bytes;
}

pub fn decode(comptime T: type, arena: std.mem.Allocator, bytes: []const u8) Error!T {
    return contracts.json.decode(T, arena, bytes, .{
        .max_schema = 1,
        .max_bytes = (contracts.Limits{}).runtime_plan_bytes,
        .limits = .{ .json_string_bytes = (contracts.Limits{}).program_blob_bytes * 2 },
    });
}

pub fn validateSnapshot(value: Snapshot, owner: Owner) Error!void {
    if (value.schema != 1 or value.generation == 0) return error.StateInvalid;
    if (value.model_version == 0 or value.release_sequence == 0) return error.StateInvalid;
    try identity(value.product_id, value.root_id, owner);
    try hashText(value.program_sha256);
    if (value.inputs.len > (contracts.Limits{}).program_items) return error.ProgramLimit;
    if (value.instances.len > (contracts.Limits{}).program_items) return error.ProgramLimit;
    if (value.migrations.len > (contracts.Limits{}).program_items) return error.ProgramLimit;
    for (value.inputs, 0..) |input, index| {
        try program.validation.identifier(input.id);
        try program.validation.inputValue(input.value, .{});
        if (program.find(Value, value.inputs[0..index], input.id) != null) {
            return error.StateInvalid;
        }
    }
    for (value.instances, 0..) |instance, index| {
        try program.validation.identifier(instance.id);
        try program.validation.identifier(instance.library_id);
        try hashText(instance.library_sha256);
        if (program.find(Instance, value.instances[0..index], instance.id) != null) {
            return error.StateInvalid;
        }
        if (instance.version == 0) return error.StateInvalid;
        if (instance.data_hex.len > (contracts.Limits{}).wasm_state_bytes * 2) {
            return error.ProgramLimit;
        }
        try hexText(instance.data_hex);
    }
    try validateHistory(value.migrations);
    try validateResources(value.resources);
}

fn validateResources(items: []const Resource) Error!void {
    if (items.len > (contracts.Limits{}).program_items) return error.ProgramLimit;
    for (items, 0..) |resource, index| {
        try program.validation.identifier(resource.id);
        try program.validation.resourcePath(resource.path);
        try hashText(resource.sha256);
        for (items[0..index]) |previous| {
            if (std.mem.eql(u8, previous.id, resource.id)) return error.StateInvalid;
            if (program.validation.pathsConflict(previous.path, resource.path)) {
                return error.StateInvalid;
            }
        }
    }
}

fn validateHistory(items: []const Migration) Error!void {
    for (items, 0..) |migration, index| {
        try program.validation.identifier(migration.id);
        if (!std.mem.eql(u8, migration.owner, "@product")) {
            try program.validation.identifier(migration.owner);
        }
        try hashText(migration.implementation_sha256);
        if (migration.from == 0 or migration.from >= migration.to) return error.StateInvalid;
        for (items[0..index]) |previous| {
            if (std.mem.eql(u8, previous.id, migration.id) and
                std.mem.eql(u8, previous.owner, migration.owner)) return error.StateInvalid;
        }
    }
}

fn hashText(text: []const u8) Error!void {
    if (text.len != 64) return error.StateInvalid;
    try hexText(text);
}

fn hexText(text: []const u8) Error!void {
    if (text.len % 2 != 0) return error.StateInvalid;
    for (text) |byte| {
        if (!(byte >= '0' and byte <= '9') and !(byte >= 'a' and byte <= 'f')) {
            return error.StateInvalid;
        }
    }
}

pub fn validatePlan(
    arena: std.mem.Allocator,
    value: Plan,
    owner: Owner,
    path: []const u8,
) Error!void {
    if (value.schema != 1 or value.host_abi != 1) return error.PlanUnsupported;
    try identity(value.product_id, value.root_id, owner);
    if (!std.unicode.utf8ValidateSlice(value.root_path)) return error.StateInvalid;
    if (!std.mem.eql(u8, value.root_path, path)) return error.StateInvalid;
    if (value.generation == 0) return error.StateInvalid;
    if (value.previous) |previous| {
        try validateSnapshot(previous, owner);
        if (previous.generation >= value.generation) return error.StateInvalid;
    }
    if (value.next) |next| {
        try validateSnapshot(next, owner);
        if (next.generation != value.generation) return error.StateInvalid;
        if (next.resources.len != value.files.len) return error.StateInvalid;
    } else if (value.files.len != 0) return error.StateInvalid;
    if (value.files.len > (contracts.Limits{}).program_items) return error.ProgramLimit;
    for (value.files, 0..) |file, index| {
        try program.validation.identifier(file.id);
        try program.validation.resourcePath(file.path);
        const bytes = try program.decodeHex(arena, file.data_hex);
        if (!std.mem.eql(u8, try program.digest(arena, bytes), file.sha256)) {
            return error.ProgramDigest;
        }
        for (value.files[0..index]) |previous| {
            if (program.validation.pathsConflict(file.path, previous.path)) {
                return error.StateInvalid;
            }
            if (std.mem.eql(u8, file.id, previous.id)) return error.StateInvalid;
        }
        const next = value.next orelse return error.StateInvalid;
        const resource = program.find(Resource, next.resources, file.id) orelse
            return error.StateInvalid;
        if (!std.mem.eql(u8, resource.path, file.path)) return error.StateInvalid;
        if (!std.mem.eql(u8, resource.sha256, file.sha256)) return error.StateInvalid;
    }
}

fn identity(product: []const u8, root: []const u8, owner: Owner) Error!void {
    try program.validation.identifier(product);
    if (root.len != 32) return error.StateInvalid;
    try hexText(root);
    if (!std.mem.eql(u8, product, owner.product_id)) return error.StateInvalid;
    if (!std.mem.eql(u8, root, owner.root_id)) return error.StateInvalid;
}

pub fn transition(rules: []const program.Migration, from: u32, to: u32) Error!?program.Migration {
    if (from == to) return null;
    for (rules) |rule| {
        if (rule.from == from and rule.to == to) return rule;
    }
    return error.UpgradeUnsupported;
}
