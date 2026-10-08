//! Bounded host descriptions of upstream WIT types, with no guest ABI encoding.
const std = @import("std");
const values = @import("value.zig");
const contracts = @import("contracts");

pub const Error = values.Error || error{
    WitInvalid,
    WitLimit,
    WitTypeMismatch,
    WitFunctionMissing,
};
pub const FieldType = struct { name: []const u8, ty: Type };
pub const CaseType = struct { name: []const u8, payload: ?*const Type = null };
pub const ResultType = struct { ok: ?*const Type = null, err: ?*const Type = null };
pub const Type = union(enum) {
    boolean,
    sint8,
    sint16,
    sint32,
    sint64,
    uint8,
    uint16,
    uint32,
    uint64,
    float32,
    float64,
    character,
    text,
    list: *const Type,
    tuple: []const Type,
    record: []const FieldType,
    variant: []const CaseType,
    enumeration: []const []const u8,
    option: *const Type,
    result: ResultType,
    flags: []const []const u8,
    own_resource,
    borrow_resource,
    unsupported: u8,
};
pub const FunctionType = struct {
    params: []const FieldType,
    result: ?*const Type = null,
    asynchronous: bool = false,
};
pub const Item = union(enum) {
    instance: []const NamedItem,
    function: FunctionType,
    resource,
    value_type: Type,
    unsupported: u8,
};
pub const NamedItem = struct { name: []const u8, item: Item };
pub const Inspection = struct { imports: []const NamedItem, exports: []const NamedItem };
pub const isTypeOnlyImport = @import("wit_imports.zig").isTypeOnlyImport;
pub const inferInputType = @import("wit_inputs.zig").inferInputType;
pub const validateInputType = @import("wit_inputs.zig").validateInputType;
pub const validateDeclaredInput = @import("wit_inputs.zig").validateDeclaredInput;
pub const compatible = @import("wit_compatibility.zig").compatible;

test {
    _ = @import("wit_compatibility.zig");
    _ = @import("wit_imports.zig");
    _ = @import("wit_inputs.zig");
}

pub fn findFunction(
    items: []const NamedItem,
    interface: []const u8,
    function: []const u8,
) Error!FunctionType {
    if (items.len > (contracts.Limits{}).component_types) return error.WitLimit;
    for (items) |entry| {
        if (interface.len == 0 and std.mem.eql(u8, entry.name, function)) {
            if (entry.item != .function) return error.WitTypeMismatch;
            return entry.item.function;
        }
        if (!std.mem.eql(u8, entry.name, interface)) continue;
        if (entry.item != .instance) return error.WitTypeMismatch;
        const members = entry.item.instance;
        if (members.len > (contracts.Limits{}).component_types) return error.WitLimit;
        for (members) |entry_point| {
            if (!std.mem.eql(u8, entry_point.name, function)) continue;
            if (entry_point.item != .function) return error.WitTypeMismatch;
            return entry_point.item.function;
        }
    }
    return error.WitFunctionMissing;
}

pub fn validateValue(value: values.Value, ty: Type) Error!void {
    try values.validate(value, .{});
    var budget: Budget = .{};
    try budget.check(value, ty, 0);
}

pub fn selectType(value: Type, fields: []const []const u8) Error!Type {
    if (fields.len > (contracts.Limits{}).component_depth) return error.WitLimit;
    var current = value;
    for (fields) |name| {
        if (current != .record) return error.WitTypeMismatch;
        if (current.record.len > (contracts.Limits{}).program_items) return error.WitLimit;
        current = for (current.record) |field| {
            if (std.mem.eql(u8, field.name, name)) break field.ty;
        } else return error.WitTypeMismatch;
    }
    return current;
}

const Budget = struct {
    nodes: u32 = 0,

    fn check(self: *Budget, value: values.Value, ty: Type, depth: u8) Error!void {
        if (self.nodes >= (contracts.Limits{}).component_types or
            depth >= (contracts.Limits{}).component_depth) return error.WitLimit;
        self.nodes += 1;
        switch (ty) {
            .boolean,
            .sint8,
            .sint16,
            .sint32,
            .sint64,
            .uint8,
            .uint16,
            .uint32,
            .uint64,
            .float32,
            .float64,
            .character,
            .text,
            => {
                if (!std.mem.eql(u8, @tagName(value), @tagName(ty))) return error.WitTypeMismatch;
            },
            .list => |element| {
                if (value == .bytes and element.* == .uint8) return;
                if (value != .list) return error.WitTypeMismatch;
                for (value.list) |item| try self.check(item, element.*, depth + 1);
            },
            .tuple => |types| {
                if (value != .tuple or value.tuple.len != types.len) return error.WitTypeMismatch;
                for (value.tuple, types) |item, item_type| try self.check(
                    item,
                    item_type,
                    depth + 1,
                );
            },
            .record => |fields| try self.record(value, fields, depth + 1),
            .variant => |cases| try self.variant(value, cases, depth + 1),
            .enumeration => |names| {
                if (value != .enumeration) return error.WitTypeMismatch;
                try member(names, value.enumeration);
            },
            .option => |inner| {
                if (value != .option) return error.WitTypeMismatch;
                if (value.option) |item| try self.check(item.*, inner.*, depth + 1);
            },
            .result => |result| {
                if (value != .result) return error.WitTypeMismatch;
                try self.payload(
                    value.result.payload,
                    if (value.result.success) result.ok else result.err,
                    depth + 1,
                );
            },
            .flags => |names| {
                if (value != .flags) return error.WitTypeMismatch;
                for (value.flags) |name| try member(names, name);
            },
            .own_resource, .borrow_resource, .unsupported => return error.WitTypeMismatch,
        }
    }

    fn record(self: *Budget, value: values.Value, fields: []const FieldType, depth: u8) Error!void {
        if (value != .record or value.record.len != fields.len) return error.WitTypeMismatch;
        for (fields) |field_type| {
            const field_value = for (value.record) |field| {
                if (std.mem.eql(u8, field.name, field_type.name)) break field.value;
            } else return error.WitTypeMismatch;
            try self.check(field_value, field_type.ty, depth);
        }
    }

    fn variant(self: *Budget, value: values.Value, cases: []const CaseType, depth: u8) Error!void {
        if (value != .variant) return error.WitTypeMismatch;
        if (cases.len > (contracts.Limits{}).component_types) return error.WitLimit;
        for (cases) |case| {
            if (std.mem.eql(u8, case.name, value.variant.name)) {
                return self.payload(value.variant.payload, case.payload, depth);
            }
        }
        return error.WitTypeMismatch;
    }

    fn payload(self: *Budget, value: ?*const values.Value, ty: ?*const Type, depth: u8) Error!void {
        if (value) |item| {
            try self.check(item.*, (ty orelse return error.WitTypeMismatch).*, depth);
        } else if (ty != null) return error.WitTypeMismatch;
    }
};

fn member(names: []const []const u8, name: []const u8) Error!void {
    if (names.len > (contracts.Limits{}).component_types) return error.WitLimit;
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return;
    }
    return error.WitTypeMismatch;
}

test "N2-TYPES-02: reflected WIT types validate named records and exact widths" {
    const ty: Type = .{ .record = &.{.{ .name = "count", .ty = .uint64 }} };
    const value: values.Value = .{ .record = &.{.{ .name = "count", .value = .{ .uint64 = 42 } }} };
    try validateValue(value, ty);
    try std.testing.expectEqual(Type.uint64, try selectType(ty, &.{"count"}));
    try std.testing.expectError(error.WitTypeMismatch, validateValue(.{ .uint32 = 42 }, .uint64));
    try std.testing.expectError(error.WitTypeMismatch, validateValue(value, .own_resource));
    try validateValue(.{ .bytes = "\xff" }, .{ .list = &.uint8 });
    try std.testing.expectError(
        error.WitTypeMismatch,
        validateValue(.{ .enumeration = "missing" }, .{ .enumeration = &.{"present"} }),
    );
}
