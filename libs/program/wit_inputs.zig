//! Parameter declarations retain complete WIT domains; defaults are never enum schemas.
const std = @import("std");
const contracts = @import("contracts");
const wit = @import("wit.zig");
const values = @import("value.zig");
const imports = @import("wit_imports.zig");
const limits = contracts.limits.default;

pub fn validateInputType(ty: wit.Type) wit.Error!void {
    std.debug.assert(limits.component_depth > 0);
    if (!try imports.isResourceFreeType(ty)) return error.WitTypeMismatch;
    // Self-compatibility also rejects duplicate named members and labels.
    try wit.compatible(ty, ty);
}

pub fn validateDeclaredInput(value: values.Value, ty: wit.Type) wit.Error!void {
    try validateInputType(ty);
    try wit.validateValue(value, ty);
}

/// Returns null when a default cannot determine a complete domain. Owns all derived metadata.
pub fn inferInputType(arena: std.mem.Allocator, value: values.Value) wit.Error!?wit.Type {
    std.debug.assert(limits.component_types > 0);
    try values.validate(value, .{});
    var inference: Inference = .{ .arena = arena };
    const ty = try inference.infer(value, 0);
    if (ty) |resolved| try validateDeclaredInput(value, resolved);
    return ty;
}

const Inference = struct {
    arena: std.mem.Allocator,
    nodes: u32 = 0,

    fn infer(self: *Inference, value: values.Value, depth: u8) wit.Error!?wit.Type {
        if (depth >= limits.component_depth or self.nodes >= limits.component_types)
            return error.WitLimit;
        self.nodes += 1;
        return switch (value) {
            .boolean => .boolean,
            .sint8 => .sint8,
            .sint16 => .sint16,
            .sint32 => .sint32,
            .sint64 => .sint64,
            .uint8 => .uint8,
            .uint16 => .uint16,
            .uint32 => .uint32,
            .uint64 => .uint64,
            .float32 => .float32,
            .float64 => .float64,
            .character => .character,
            .text => .text,
            .bytes => .{ .list = &.uint8 },
            .list => |items| self.list(items, depth),
            .tuple => |items| self.tuple(items, depth),
            .record => |fields| self.record(fields, depth),
            .option => |payload| blk: {
                const child = payload orelse break :blk null;
                const ty = try self.infer(child.*, depth + 1) orelse break :blk null;
                break :blk .{ .option = try self.box(ty) };
            },
            .enumeration, .flags, .variant, .result => null,
        };
    }

    fn list(self: *Inference, items: []const values.Value, depth: u8) wit.Error!?wit.Type {
        if (items.len == 0) return null;
        if (items.len > limits.component_types) return error.WitLimit;
        const element = try self.infer(items[0], depth + 1) orelse return null;
        for (items[1..]) |item| {
            const candidate = try self.infer(item, depth + 1) orelse return null;
            try wit.compatible(element, candidate);
        }
        return .{ .list = try self.box(element) };
    }

    fn tuple(self: *Inference, items: []const values.Value, depth: u8) wit.Error!?wit.Type {
        if (items.len > limits.component_types) return error.WitLimit;
        const types = try self.arena.alloc(wit.Type, items.len);
        for (items, types) |item, *ty| {
            ty.* = try self.infer(item, depth + 1) orelse return null;
        }
        return .{ .tuple = types };
    }

    fn record(self: *Inference, fields: []const values.Field, depth: u8) wit.Error!?wit.Type {
        if (fields.len > limits.program_items) return error.WitLimit;
        const types = try self.arena.alloc(wit.FieldType, fields.len);
        for (fields, types) |field, *ty| {
            const inferred = try self.infer(field.value, depth + 1) orelse return null;
            ty.* = .{ .name = try self.arena.dupe(u8, field.name), .ty = inferred };
        }
        return .{ .record = types };
    }

    fn box(self: *Inference, ty: wit.Type) wit.Error!*const wit.Type {
        const pointer = try self.arena.create(wit.Type);
        pointer.* = ty;
        return pointer;
    }
};

test "N2-TYPES-03: determinate defaults infer full types rather than singleton values" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const boolean = (try inferInputType(allocator, .{ .boolean = true })).?;
    try validateDeclaredInput(.{ .boolean = false }, boolean);
    try std.testing.expectError(
        error.WitTypeMismatch,
        validateDeclaredInput(.{ .text = "false" }, boolean),
    );
    const list = (try inferInputType(allocator, .{ .list = &.{.{ .uint64 = 7 }} })).?;
    try validateDeclaredInput(.{ .list = &.{} }, list);
    try std.testing.expectError(
        error.WitTypeMismatch,
        validateDeclaredInput(.{ .list = &.{.{ .uint32 = 7 }} }, list),
    );
    var text: values.Value = .{ .text = "default" };
    const option = (try inferInputType(allocator, .{ .option = &text })).?;
    try validateDeclaredInput(.{ .option = null }, option);
    const record = (try inferInputType(allocator, .{ .record = &.{
        .{ .name = "count", .value = .{ .uint64 = 1 } },
        .{ .name = "label", .value = .{ .text = "x" } },
    } })).?;
    try validateDeclaredInput(.{ .record = &.{
        .{ .name = "label", .value = .{ .text = "different" } },
        .{ .name = "count", .value = .{ .uint64 = 99 } },
    } }, record);
}

test "N2-TYPES-03: empty and open domains require an actual use-site declaration" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    for ([_]values.Value{
        .{ .list = &.{} },                 .{ .option = null },
        // Selected labels cannot describe the complete enum or flags domain.
        .{ .enumeration = "stable" },      .{ .flags = &.{"read"} },
        // The selected branch says nothing about unselected payload types.
        .{ .variant = .{ .name = "ok" } }, .{ .result = .{ .success = true } },
    }) |default| try std.testing.expect(try inferInputType(arena.allocator(), default) == null);
    const complete: wit.Type = .{ .enumeration = &.{ "stable", "preview" } };
    try validateDeclaredInput(.{ .enumeration = "stable" }, complete);
    try validateDeclaredInput(.{ .enumeration = "preview" }, complete);
    try std.testing.expectError(
        error.WitTypeMismatch,
        validateDeclaredInput(.{ .enumeration = "unknown" }, complete),
    );
    try std.testing.expectError(
        error.WitTypeMismatch,
        validateInputType(.{ .option = &.own_resource }),
    );
    try std.testing.expectError(
        error.WitInvalid,
        validateInputType(.{ .enumeration = &.{ "same", "same" } }),
    );
}
