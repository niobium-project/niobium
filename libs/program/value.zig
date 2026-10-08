//! Lossless host values for standard WIT calls. No guest memory layout crosses this model.
const std = @import("std");
const contracts = @import("contracts");

pub const Error = error{ ValueInvalid, ValueLimit, OutOfMemory };
pub const Field = struct { name: []const u8, value: Value };
pub const Variant = struct { name: []const u8, payload: ?*const Value = null };
pub const Result = struct { success: bool, payload: ?*const Value = null };
pub const Value = union(enum) {
    boolean: bool,
    uint8: u8,
    uint16: u16,
    uint32: u32,
    uint64: u64,
    sint8: i8,
    sint16: i16,
    sint32: i32,
    sint64: i64,
    float32: f32,
    float64: f64,
    character: u32,
    text: []const u8,
    bytes: []const u8,
    list: []const Value,
    tuple: []const Value,
    record: []const Field,
    variant: Variant,
    enumeration: []const u8,
    option: ?*const Value,
    result: Result,
    flags: []const []const u8,
};

const Budget = struct {
    nodes: usize = 0,
    bytes: usize = 0,
    limits: contracts.Limits,

    fn charge(self: *Budget, size: usize) Error!void {
        if (size > self.limits.program_bytes - self.bytes) return error.ValueLimit;
        self.bytes += size;
    }

    fn string(self: *Budget, text: []const u8) Error!void {
        if (!std.unicode.utf8ValidateSlice(text)) return error.ValueInvalid;
        try self.charge(text.len);
    }

    fn item(self: *Budget, value: Value, depth: u8) Error!void {
        if (depth >= self.limits.component_depth or self.nodes >= self.limits.component_types)
            return error.ValueLimit;
        self.nodes += 1;
        switch (value) {
            .boolean, .uint8, .uint16, .uint32, .uint64, .sint8, .sint16, .sint32, .sint64 => {},
            .float32 => |v| if (!std.math.isFinite(v)) return error.ValueInvalid,
            .float64 => |v| if (!std.math.isFinite(v)) return error.ValueInvalid,
            .character => |v| {
                if (v > 0x10ffff or (v >= 0xd800 and v <= 0xdfff)) return error.ValueInvalid;
            },
            .text, .enumeration => |v| try self.string(v),
            .bytes => |v| try self.charge(v.len),
            .list, .tuple => |items| {
                if (items.len > self.limits.component_types) return error.ValueLimit;
                for (items) |v| try self.item(v, depth + 1);
            },
            .record => |members| try self.fields(members, depth + 1),
            .variant => |v| {
                try self.label(v.name);
                if (v.payload) |payload| try self.item(payload.*, depth + 1);
            },
            .option => |v| if (v) |payload| try self.item(payload.*, depth + 1),
            .result => |v| if (v.payload) |payload| try self.item(payload.*, depth + 1),
            .flags => |items| {
                if (items.len > self.limits.program_items) return error.ValueLimit;
                for (items, 0..) |name, index| {
                    try self.label(name);
                    for (items[0..index]) |old| {
                        if (std.mem.eql(u8, old, name)) return error.ValueInvalid;
                    }
                }
            },
        }
    }

    fn label(self: *Budget, name: []const u8) Error!void {
        if (name.len == 0 or name.len > 128 or std.mem.indexOfScalar(u8, name, 0) != null)
            return error.ValueInvalid;
        try self.string(name);
    }

    fn fields(self: *Budget, items: []const Field, depth: u8) Error!void {
        if (items.len > self.limits.program_items) return error.ValueLimit;
        for (items, 0..) |field, index| {
            try self.label(field.name);
            for (items[0..index]) |old| {
                if (std.mem.eql(u8, old.name, field.name)) return error.ValueInvalid;
            }
            try self.item(field.value, depth);
        }
    }
};

pub const Usage = struct { nodes: u32, bytes: u32 };

pub fn measure(value: Value, limits: contracts.Limits) Error!Usage {
    var budget: Budget = .{ .limits = limits };
    try budget.item(value, 0);
    return .{
        .nodes = std.math.cast(u32, budget.nodes) orelse return error.ValueLimit,
        .bytes = std.math.cast(u32, budget.bytes) orelse return error.ValueLimit,
    };
}

pub fn validate(value: Value, limits: contracts.Limits) Error!void {
    const usage = try measure(value, limits);
    std.debug.assert(usage.nodes > 0);
}

pub fn select(value: Value, fields: []const []const u8) Error!Value {
    try validate(value, .{});
    if (fields.len > (contracts.Limits{}).component_depth) return error.ValueLimit;
    var current = value;
    for (fields) |name| {
        if (current != .record) return error.ValueInvalid;
        current = for (current.record) |field| {
            if (std.mem.eql(u8, field.name, name)) break field.value;
        } else return error.ValueInvalid;
    }
    return current;
}

test "N2-TYPES-01: WIT host values preserve exact integer widths and reject invalid data" {
    const largest: Value = .{ .uint64 = std.math.maxInt(u64) };
    try validate(largest, .{});
    const record: Value = .{ .record = &.{.{ .name = "count", .value = largest }} };
    try std.testing.expectEqual(largest, try select(record, &.{"count"}));
    try std.testing.expectError(error.ValueInvalid, validate(.{ .text = "\xff" }, .{}));
    try std.testing.expectError(error.ValueInvalid, validate(.{ .character = 0xd800 }, .{}));
    const nan: Value = .{ .float64 = std.math.nan(f64) };
    try std.testing.expectError(error.ValueInvalid, validate(nan, .{}));
    try std.testing.expectError(error.ValueInvalid, validate(.{ .flags = &.{ "a", "a" } }, .{}));
    try std.testing.expectError(error.ValueLimit, validate(record, .{ .component_depth = 1 }));
    const oversized: Value = .{ .bytes = "long" };
    try std.testing.expectError(error.ValueLimit, validate(oversized, .{ .program_bytes = 3 }));
}
