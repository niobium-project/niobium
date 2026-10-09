//! Structural compatibility of reflected WIT types; no guest ABI layout is inferred here.

const std = @import("std");
const contracts = @import("contracts");
const wit = @import("wit.zig");

pub fn compatible(source: wit.Type, destination: wit.Type) wit.Error!void {
    var budget: Budget = .{};
    try budget.match(source, destination, 0);
}

const Budget = struct {
    nodes: u32 = 0,

    fn match(self: *Budget, source: wit.Type, target: wit.Type, depth: u8) wit.Error!void {
        if (depth >= contracts.limits.default.component_depth or
            self.nodes >= contracts.limits.default.component_types) return error.WitLimit;
        self.nodes += 1;
        if (std.meta.activeTag(source) != std.meta.activeTag(target)) return error.WitTypeMismatch;
        switch (source) {
            .own_resource, .borrow_resource, .unsupported => return error.WitTypeMismatch,
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
            => {},
            .list => |child| try self.match(child.*, target.list.*, depth + 1),
            .option => |child| try self.match(child.*, target.option.*, depth + 1),
            .tuple => |items| {
                if (items.len != target.tuple.len) return error.WitTypeMismatch;
                if (items.len > contracts.limits.default.component_types) return error.WitLimit;
                for (items, target.tuple) |left, right| try self.match(left, right, depth + 1);
            },
            .record => |fields| try self.record(fields, target.record, depth + 1),
            .variant => |cases| try self.variant(cases, target.variant, depth + 1),
            .enumeration => |names| try labels(names, target.enumeration),
            .flags => |names| try labels(names, target.flags),
            .result => |result| {
                try self.optional(result.ok, target.result.ok, depth + 1);
                try self.optional(result.err, target.result.err, depth + 1);
            },
        }
    }

    fn record(
        self: *Budget,
        source: []const wit.FieldType,
        target: []const wit.FieldType,
        depth: u8,
    ) wit.Error!void {
        if (source.len != target.len) return error.WitTypeMismatch;
        if (source.len > contracts.limits.default.program_items) return error.WitLimit;
        for (source, 0..) |field, index| {
            for (source[0..index]) |prior| {
                if (std.mem.eql(u8, prior.name, field.name)) return error.WitInvalid;
            }
            const counterpart = for (target) |other| {
                if (std.mem.eql(u8, field.name, other.name)) break other;
            } else return error.WitTypeMismatch;
            try self.match(field.ty, counterpart.ty, depth);
        }
    }

    fn variant(
        self: *Budget,
        source: []const wit.CaseType,
        target: []const wit.CaseType,
        depth: u8,
    ) wit.Error!void {
        if (source.len != target.len) return error.WitTypeMismatch;
        if (source.len > contracts.limits.default.component_types) return error.WitLimit;
        for (source, 0..) |item, index| {
            for (source[0..index]) |prior| {
                if (std.mem.eql(u8, prior.name, item.name)) return error.WitInvalid;
            }
            const counterpart = for (target) |other| {
                if (std.mem.eql(u8, item.name, other.name)) break other;
            } else return error.WitTypeMismatch;
            try self.optional(item.payload, counterpart.payload, depth);
        }
    }

    fn optional(
        self: *Budget,
        source: ?*const wit.Type,
        target: ?*const wit.Type,
        depth: u8,
    ) wit.Error!void {
        if ((source == null) != (target == null)) return error.WitTypeMismatch;
        if (source) |value| try self.match(value.*, target.?.*, depth);
    }
};

fn labels(source: []const []const u8, target: []const []const u8) wit.Error!void {
    if (source.len != target.len) return error.WitTypeMismatch;
    if (source.len > contracts.limits.default.component_types) return error.WitLimit;
    for (source, 0..) |name, index| {
        for (source[0..index]) |prior| {
            if (std.mem.eql(u8, name, prior)) return error.WitInvalid;
        }
        const found = for (target) |other| {
            if (std.mem.eql(u8, name, other)) break true;
        } else false;
        if (!found) return error.WitTypeMismatch;
    }
}

test "N2-TYPES-02 typed graph edges retain integer widths and named record fields" {
    try compatible(.{
        .record = &.{ .{ .name = "a", .ty = .uint64 }, .{ .name = "b", .ty = .text } },
    }, .{ .record = &.{
        .{ .name = "b", .ty = .text }, .{ .name = "a", .ty = .uint64 },
    } });
    try std.testing.expectError(error.WitTypeMismatch, compatible(.uint64, .uint32));
    try std.testing.expectError(error.WitTypeMismatch, compatible(.own_resource, .own_resource));
    try std.testing.expectError(error.WitTypeMismatch, compatible(
        .{ .enumeration = &.{ "a", "b" } },
        .{ .enumeration = &.{ "a", "c" } },
    ));
}
