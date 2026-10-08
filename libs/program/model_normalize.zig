//! Canonical names in standard aggregate values; ordered sequences keep their order.

const std = @import("std");
const contracts = @import("contracts");
const program = @import("root.zig");
const model = @import("model.zig");

pub const Normalizer = struct {
    arena: std.mem.Allocator,

    pub fn binding(self: Normalizer, item: model.Binding, depth: u8) model.Error!model.Binding {
        if (depth >= contracts.limits.default.component_depth) return error.ProgramLimit;
        return switch (item) {
            .literal => |literal| .{ .literal = try self.value(literal, depth) },
            .record => |fields| blk: {
                const copies = try self.arena.dupe(model.BindingField, fields);
                for (copies) |*field| field.binding = try self.binding(field.binding, depth + 1);
                std.mem.sort(model.BindingField, copies, {}, struct {
                    fn less(_: void, a: model.BindingField, b: model.BindingField) bool {
                        return std.mem.lessThan(u8, a.name, b.name);
                    }
                }.less);
                break :blk .{ .record = copies };
            },
            .list, .tuple => |items| blk: {
                const copies = try self.arena.dupe(model.Binding, items);
                for (copies) |*child| child.* = try self.binding(child.*, depth + 1);
                break :blk if (item == .list) .{ .list = copies } else .{ .tuple = copies };
            },
            .some => |child| blk: {
                const copy = try self.arena.create(model.Binding);
                copy.* = try self.binding(child.*, depth + 1);
                break :blk .{ .some = copy };
            },
            else => item,
        };
    }

    pub fn value(
        self: Normalizer,
        item: program.value.Value,
        depth: u8,
    ) model.Error!program.value.Value {
        if (depth >= contracts.limits.default.component_depth) return error.ProgramLimit;
        return switch (item) {
            .record => |fields| blk: {
                const copies = try self.arena.dupe(program.value.Field, fields);
                for (copies) |*field| field.value = try self.value(field.value, depth + 1);
                std.mem.sort(program.value.Field, copies, {}, struct {
                    fn less(_: void, a: program.value.Field, b: program.value.Field) bool {
                        return std.mem.lessThan(u8, a.name, b.name);
                    }
                }.less);
                break :blk .{ .record = copies };
            },
            .list, .tuple => |items| blk: {
                const copies = try self.arena.dupe(program.value.Value, items);
                for (copies) |*child| child.* = try self.value(child.*, depth + 1);
                break :blk if (item == .list) .{ .list = copies } else .{ .tuple = copies };
            },
            .variant => |variant| .{ .variant = .{
                .name = variant.name,
                .payload = try self.optional(variant.payload, depth + 1),
            } },
            .option => |child| .{ .option = try self.optional(child, depth + 1) },
            .result => |result| .{ .result = .{
                .success = result.success,
                .payload = try self.optional(result.payload, depth + 1),
            } },
            .flags => |names| blk: {
                const copies = try self.arena.dupe([]const u8, names);
                std.mem.sort([]const u8, copies, {}, struct {
                    fn less(_: void, a: []const u8, b: []const u8) bool {
                        return std.mem.lessThan(u8, a, b);
                    }
                }.less);
                break :blk .{ .flags = copies };
            },
            else => item,
        };
    }

    fn optional(
        self: Normalizer,
        item: ?*const program.value.Value,
        depth: u8,
    ) model.Error!?*const program.value.Value {
        const child = item orelse return null;
        const copy = try self.arena.create(program.value.Value);
        copy.* = try self.value(child.*, depth);
        return copy;
    }
};
