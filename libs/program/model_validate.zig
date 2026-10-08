//! Structural v2 checks precede upstream Component type inspection and machine effects.

const std = @import("std");
const contracts = @import("contracts");
const content = @import("content");
const access = @import("access_policy");
const program = @import("root.zig");
const model = @import("model.zig");
const Error = model.Error;
const shape = @import("model_shape.zig");
pub const validateCallShape = shape.validateCallShape;
pub const validateObservationShape = shape.validateObservationShape;
pub const validateBindingShape = shape.validateBindingShape;

pub fn validate(product: model.Product, limits: contracts.Limits) Error!void {
    std.debug.assert(limits.program_items > 0);
    if (product.calls.len > contracts.limits.default.program_items) return error.ProgramLimit;
    if (product.schema != 2 or product.runtime_abi != 2) return error.ProgramUnsupported;
    try program.validation.identifier(product.id);
    if (product.release_sequence == 0 or product.model_version == 0) return error.ProgramInvalid;
    try program.profile.require(product.profile, product.target, &.{});
    inline for (.{
        "inputs", "libraries", "containers", "roots", "grants", "observations", "calls", "upgrades",
    }) |field| {
        try unique(@field(product, field), limits);
    }
    var budget: shape.Budget = .{ .limits = limits };
    for (product.inputs) |input| {
        try budget.literal(input.default, 0);
        if (input.resolved_type) |ty| try program.wit.validateDeclaredInput(input.default, ty);
    }
    for (product.libraries) |library| {
        try content.names.check(library.member, limits);
        try digest(library.sha256);
        if (library.bytes == 0 or library.bytes > limits.component_bytes) return error.ProgramLimit;
        try program.profile.require(product.profile, product.target, library.requires);
    }
    for (product.containers) |container| {
        try content.names.check(container.member, limits);
        if (container.reference.bytes > limits.expanded_bytes) return error.ProgramLimit;
    }
    try members(product);
    for (product.roots) |root| if (root.scope != .user) return error.ProgramUnsupported;
    if (product.roots.len > 0) {
        if (program.find(model.Root, product.roots, product.state_root) == null) {
            return error.ProgramReference;
        }
    } else if (product.state_root.len != 0) return error.ProgramReference;
    for (product.grants) |grant| try checkGrant(product, grant, limits);
    for (product.observations) |observation| {
        try budget.observation(observation);
        try checkObservation(product, observation, limits);
    }
    for (product.calls) |call| {
        try budget.call(call);
        try checkCall(product, call, limits);
    }
    try upgradeEdges(product.upgrades, product.model_version);
    // SAFETY: schedule fills every returned position before it is observed.
    var storage: [contracts.limits.default.program_items]usize = undefined;
    try schedule(product.calls, &storage);
}

fn unique(items: anytype, limits: contracts.Limits) Error!void {
    if (items.len > limits.program_items) return error.ProgramLimit;
    for (items, 0..) |item, index| {
        try program.validation.identifier(item.id);
        for (items[0..index]) |prior| {
            if (std.mem.eql(u8, prior.id, item.id)) return error.ProgramDuplicate;
        }
    }
}

pub fn text(value: []const u8, empty: bool) Error!void {
    if ((!empty and value.len == 0) or value.len > contracts.limits.default.path_bytes) {
        return error.ProgramLimit;
    }
    if (!std.unicode.utf8ValidateSlice(value) or std.mem.findScalar(u8, value, 0) != null) {
        return error.ProgramInvalid;
    }
}

fn digest(value: []const u8) Error!void {
    if (contracts.ids.parseHex32(value) == null) return error.ProgramDigest;
}

fn members(product: model.Product) Error!void {
    for (product.libraries, 0..) |library, index| {
        for (product.libraries[0..index]) |other| {
            if (std.mem.eql(u8, library.member, other.member)) return error.ProgramDuplicate;
        }
        for (product.containers) |container| {
            if (std.mem.eql(u8, library.member, container.member) or
                std.mem.eql(u8, library.id, container.id)) return error.ProgramDuplicate;
        }
    }
    for (product.containers, 0..) |container, index| {
        for (product.containers[0..index]) |other| {
            if (std.mem.eql(u8, container.member, other.member)) return error.ProgramDuplicate;
        }
    }
}

fn checkGrant(product: model.Product, grant: model.Grant, limits: contracts.Limits) Error!void {
    if (program.find(model.Root, product.roots, grant.root) == null) return error.ProgramReference;
    try program.profile.require(product.profile, product.target, &.{grant.primitive});
    if (grant.prefix.len > 0) try content.names.check(grant.prefix, limits);
    if (grant.max_entries == 0 or grant.max_entries > limits.files_per_artifact or
        grant.max_bytes == 0 or grant.max_bytes > limits.expanded_bytes) return error.ProgramLimit;
    if (grant.file_access.kind != .file or grant.directory_access.kind != .directory) {
        return error.ProgramAuthority;
    }
    try access.validate(grant.file_access);
    try access.validate(grant.directory_access);
}

fn checkObservation(
    product: model.Product,
    observation: model.Observation,
    limits: contracts.Limits,
) Error!void {
    try program.profile.require(product.profile, product.target, &.{observation.primitive});
    try text(observation.function, false);
    if (observation.arguments.len > limits.program_items) return error.ProgramLimit;
    for (observation.arguments) |argument| try program.value.validate(argument, limits);
    if (observation.grant) |id| {
        const grant = program.find(
            model.Grant,
            product.grants,
            id,
        ) orelse return error.ProgramReference;
        if (!sameRequirement(grant.primitive, observation.primitive)) return error.ProgramAuthority;
    }
}

fn sameRequirement(a: program.profile.Requirement, b: program.profile.Requirement) bool {
    return std.mem.eql(u8, a.id, b.id) and a.version == b.version;
}

fn checkCall(product: model.Product, call: model.Call, limits: contracts.Limits) Error!void {
    if (program.find(model.Library, product.libraries, call.library) == null) {
        return error.ProgramReference;
    }
    try text(call.interface, true);
    try text(call.function, false);
    if (call.result_role != .plan and call.migrations.len != 0) return error.ProgramInvalid;
    if (call.arguments.len > limits.program_items or call.state_version == 0)
        return error.ProgramLimit;
    try references(model.Grant, product.grants, call.grants, limits);
    try references(model.Call, product.calls, call.after, limits);
    const walker: ReferenceWalker = .{ .product = product, .call = call, .limits = limits };
    for (call.arguments) |argument| try walker.visit(argument, 0);
    try unique(call.migrations, limits);
    for (call.migrations, 0..) |migration, index| {
        if (migration.from == 0 or migration.from >= migration.to or
            migration.to != call.state_version)
        {
            return error.ProgramInvalid;
        }
        for (call.migrations[0..index]) |other| {
            if (other.from == migration.from) return error.ProgramDuplicate;
        }
        const library = program.find(model.Library, product.libraries, migration.library) orelse
            return error.ProgramReference;
        try digest(migration.implementation_sha256);
        if (!std.mem.eql(u8, library.sha256, migration.implementation_sha256)) {
            return error.ProgramDigest;
        }
        try text(migration.interface, true);
        try text(migration.function, false);
    }
}

const ReferenceWalker = struct {
    product: model.Product,
    call: model.Call,
    limits: contracts.Limits,

    fn visit(self: ReferenceWalker, argument: model.Binding, depth: u8) Error!void {
        if (depth >= self.limits.component_depth) return error.ProgramLimit;
        const product = self.product;
        const limits = self.limits;
        switch (argument) {
            .literal => {},
            .input => |id| {
                if (program.find(
                    model.Input,
                    product.inputs,
                    id,
                ) == null) return error.ProgramReference;
            },
            .node_result => |projection| try project(model.Call, product.calls, projection, limits),
            .observation => |projection| try project(
                model.Observation,
                product.observations,
                projection,
                limits,
            ),
            .previous_state => if (self.call.result_role != .plan) return error.ProgramInvalid,
            .record => |fields| for (fields) |field| {
                try self.visit(field.binding, depth + 1);
            },
            .list, .tuple => |items| for (items) |item| {
                try self.visit(item, depth + 1);
            },
            .some => |item| try self.visit(item.*, depth + 1),
        }
    }
};

fn references(
    comptime T: type,
    source: []const T,
    ids: []const []const u8,
    limits: contracts.Limits,
) Error!void {
    if (ids.len > limits.program_items) return error.ProgramLimit;
    for (ids, 0..) |id, index| {
        if (program.find(T, source, id) == null) return error.ProgramReference;
        for (ids[0..index]) |other| if (std.mem.eql(u8, id, other)) return error.ProgramDuplicate;
    }
}

fn project(
    comptime T: type,
    source: []const T,
    projection: model.Projection,
    limits: contracts.Limits,
) Error!void {
    if (program.find(T, source, projection.id) == null) return error.ProgramReference;
    if (projection.fields.len > limits.component_depth) return error.ProgramLimit;
    for (projection.fields) |field| try text(field, false);
}

fn upgradeEdges(items: []const program.Migration, target: u32) Error!void {
    for (items, 0..) |migration, index| {
        if (migration.from == 0 or migration.from >= migration.to or migration.to != target) {
            return error.ProgramInvalid;
        }
        for (items[0..index]) |other| {
            if (other.from == migration.from) return error.ProgramDuplicate;
        }
    }
}

pub fn order(arena: std.mem.Allocator, calls: []const model.Call) Error![]const usize {
    if (calls.len > contracts.limits.default.program_items) return error.ProgramLimit;
    const indices = try arena.alloc(usize, calls.len);
    try schedule(calls, indices);
    return indices;
}

fn schedule(calls: []const model.Call, output: []usize) Error!void {
    std.debug.assert(output.len >= calls.len);
    var ready: [contracts.limits.default.program_items]bool = @splat(false);
    for (0..calls.len) |position| {
        var chosen: ?usize = null;
        for (calls, 0..) |call, index| {
            if (ready[index] or !try dependenciesReady(calls, call, &ready)) continue;
            if (chosen == null or std.mem.lessThan(u8, call.id, calls[chosen.?].id)) chosen = index;
        }
        const index = chosen orelse return error.ProgramCycle;
        output[position] = index;
        ready[index] = true;
    }
}

fn dependenciesReady(calls: []const model.Call, call: model.Call, ready: []const bool) Error!bool {
    for (call.after) |id| if (!nodeReady(calls, id, ready)) return false;
    const walker: ReadyWalker = .{ .calls = calls, .ready = ready };
    for (call.arguments) |argument| if (!try walker.visit(argument, 0)) return false;
    return true;
}

const ReadyWalker = struct {
    calls: []const model.Call,
    ready: []const bool,

    fn visit(self: ReadyWalker, value: model.Binding, depth: u8) Error!bool {
        if (depth >= contracts.limits.default.component_depth) return error.ProgramLimit;
        return switch (value) {
            .node_result => |projection| nodeReady(self.calls, projection.id, self.ready),
            .record => |fields| blk: {
                for (fields) |field| if (!try self.visit(
                    field.binding,
                    depth + 1,
                )) break :blk false;
                break :blk true;
            },
            .list, .tuple => |items| blk: {
                for (items) |item| if (!try self.visit(item, depth + 1)) break :blk false;
                break :blk true;
            },
            .some => |item| self.visit(item.*, depth + 1),
            else => true,
        };
    }
};

fn nodeReady(calls: []const model.Call, id: []const u8, ready: []const bool) bool {
    for (calls, 0..) |call, index| if (std.mem.eql(u8, id, call.id)) return ready[index];
    return false;
}
