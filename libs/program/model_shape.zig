//! Bounded native author values, before serialization or forward-reference resolution.

const std = @import("std");
const contracts = @import("contracts");
const program = @import("root.zig");
const model = @import("model.zig");
const check = @import("model_validate.zig");

pub const Budget = struct {
    limits: contracts.Limits,
    nodes: u32 = 0,
    bytes: u32 = 0,

    fn text(self: *Budget, text_: []const u8) model.Error!void {
        if (text_.len > self.limits.program_bytes - self.bytes) return error.ProgramLimit;
        self.bytes += std.math.cast(u32, text_.len) orelse return error.ProgramLimit;
    }

    pub fn literal(self: *Budget, value: program.value.Value, depth: u8) model.Error!void {
        if (depth >= self.limits.component_depth or self.nodes >= self.limits.component_types) {
            return error.ProgramLimit;
        }
        var remaining = self.limits;
        remaining.component_depth -= depth;
        remaining.component_types -= std.math.cast(
            u16,
            self.nodes,
        ) orelse return error.ProgramLimit;
        remaining.program_bytes -= self.bytes;
        const usage = try program.value.measure(value, remaining);
        self.nodes += usage.nodes;
        self.bytes += usage.bytes;
    }

    pub fn binding(self: *Budget, value: model.Binding, depth: u8) model.Error!void {
        if (depth >= self.limits.component_depth or self.nodes >= self.limits.component_types) {
            return error.ProgramLimit;
        }
        self.nodes += 1;
        switch (value) {
            .literal => |literal_value| try self.literal(literal_value, depth),
            .input => |id| {
                try program.validation.identifier(id);
                try self.text(id);
            },
            .node_result, .observation => |projection| {
                try program.validation.identifier(projection.id);
                try self.text(projection.id);
                if (projection.fields.len > self.limits.component_depth) return error.ProgramLimit;
                for (projection.fields) |field| {
                    try check.text(field, false);
                    try self.text(field);
                }
            },
            .previous_state => {},
            .record => |fields| {
                if (fields.len > self.limits.program_items) return error.ProgramLimit;
                for (fields, 0..) |field, index| {
                    try check.text(field.name, false);
                    try self.text(field.name);
                    for (fields[0..index]) |prior| {
                        if (std.mem.eql(u8, prior.name, field.name)) return error.ProgramDuplicate;
                    }
                    try self.binding(field.binding, depth + 1);
                }
            },
            .list, .tuple => |items| {
                if (items.len > self.limits.component_types) return error.ProgramLimit;
                for (items) |item| try self.binding(item, depth + 1);
            },
            .some => |item| try self.binding(item.*, depth + 1),
        }
    }

    pub fn call(self: *Budget, value: model.Call) model.Error!void {
        try program.validation.identifier(value.id);
        try program.validation.identifier(value.library);
        try check.text(value.interface, true);
        try check.text(value.function, false);
        if (value.state_version == 0 or value.arguments.len > self.limits.program_items or
            value.migrations.len > self.limits.program_items) return error.ProgramLimit;
        try ids(value.after, self.limits);
        try ids(value.grants, self.limits);
        for (value.arguments) |item| try self.binding(item, 0);
        for (value.migrations) |migration| {
            try program.validation.identifier(migration.id);
            try program.validation.identifier(migration.library);
            try check.text(migration.interface, true);
            try check.text(migration.function, false);
            if (contracts.ids.parseHex32(migration.implementation_sha256) == null) {
                return error.ProgramDigest;
            }
        }
    }

    pub fn observation(self: *Budget, value: model.Observation) model.Error!void {
        try program.validation.identifier(value.id);
        try program.profile.validateRequirements(&.{value.primitive});
        try check.text(value.function, false);
        if (value.arguments.len > self.limits.program_items) return error.ProgramLimit;
        if (value.grant) |grant| try program.validation.identifier(grant);
        for (value.arguments) |item| try self.literal(item, 0);
    }
};

fn ids(items: []const []const u8, limits: contracts.Limits) model.Error!void {
    if (items.len > limits.program_items) return error.ProgramLimit;
    for (items, 0..) |id, index| {
        try program.validation.identifier(id);
        for (items[0..index]) |prior| if (std.mem.eql(u8, prior, id)) return error.ProgramDuplicate;
    }
}

pub fn validateCallShape(value: model.Call, limits: contracts.Limits) model.Error!void {
    var budget: Budget = .{ .limits = limits };
    try budget.call(value);
}

pub fn validateObservationShape(
    value: model.Observation,
    limits: contracts.Limits,
) model.Error!void {
    var budget: Budget = .{ .limits = limits };
    try budget.observation(value);
}

pub fn validateBindingShape(value: model.Binding, limits: contracts.Limits) model.Error!void {
    var budget: Budget = .{ .limits = limits };
    try budget.binding(value, 0);
}
