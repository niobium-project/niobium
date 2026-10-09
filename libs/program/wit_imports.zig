//! Type-only imports convey no callable host authority and use standard structural WIT types.
const std = @import("std");
const contracts = @import("contracts");
const wit = @import("wit.zig");
const limits = contracts.limits.default;
pub fn isTypeOnlyImport(item: wit.NamedItem) wit.Error!bool {
    try name(item.name);
    if (std.mem.startsWith(u8, item.name, "wasi:")) return false;
    if (item.item != .instance or item.item.instance.len == 0) return false;
    const members = item.item.instance;
    if (members.len > limits.program_items) return error.WitLimit;
    var budget: Budget = .{};
    for (members) |member| {
        try name(member.name);
        if (member.item != .value_type) return false;
        if (!try budget.check(member.item.value_type, 0)) return false;
    }
    return true;
}
pub fn isResourceFreeType(ty: wit.Type) wit.Error!bool {
    var budget: Budget = .{};
    return budget.check(ty, 0);
}

const Budget = struct {
    nodes: u32 = 0,
    fn check(self: *Budget, ty: wit.Type, depth: u8) wit.Error!bool {
        if (depth >= limits.component_depth or self.nodes >= limits.component_types)
            return error.WitLimit;
        self.nodes += 1;
        return switch (ty) {
            .own_resource, .borrow_resource, .unsupported => false,
            .list, .option => |child| self.check(child.*, depth + 1),
            .tuple => |children| self.sequence(children, depth),
            .record => |fields| self.record(fields, depth),
            .variant => |cases| self.variant(cases, depth),
            .result => |result| (try self.optional(result.ok, depth)) and
                (try self.optional(result.err, depth)),
            .enumeration, .flags => |names| blk: {
                if (names.len > limits.program_items) return error.WitLimit;
                for (names) |label| try name(label);
                break :blk true;
            },
            else => true,
        };
    }
    fn optional(self: *Budget, ty: ?*const wit.Type, depth: u8) wit.Error!bool {
        return if (ty) |child| self.check(child.*, depth + 1) else true;
    }
    fn sequence(self: *Budget, children: []const wit.Type, depth: u8) wit.Error!bool {
        if (children.len > limits.program_items) return error.WitLimit;
        for (children) |child| if (!try self.check(child, depth + 1)) return false;
        return true;
    }
    fn record(self: *Budget, fields: []const wit.FieldType, depth: u8) wit.Error!bool {
        if (fields.len > limits.program_items) return error.WitLimit;
        for (fields) |field| {
            try name(field.name);
            if (!try self.check(field.ty, depth + 1)) return false;
        }
        return true;
    }
    fn variant(self: *Budget, cases: []const wit.CaseType, depth: u8) wit.Error!bool {
        if (cases.len > limits.program_items) return error.WitLimit;
        for (cases) |case| {
            try name(case.name);
            if (!try self.optional(case.payload, depth)) return false;
        }
        return true;
    }
};
fn name(value: []const u8) wit.Error!void {
    if (value.len == 0 or value.len > 256 or !std.unicode.utf8ValidateSlice(value))
        return error.WitInvalid;
    for (value) |byte| if (byte < 0x20 or byte == 0x7f) return error.WitInvalid;
}
test "N2-COMPONENT-02: type-only imports reject empty, mixed and nested resource authority" {
    const integer: wit.NamedItem = .{ .name = "count", .item = .{ .value_type = .uint64 } };
    const pure: wit.NamedItem = .{
        .name = "example:types/data@1.0.0",
        .item = .{ .instance = &.{integer} },
    };
    try std.testing.expect(try isTypeOnlyImport(pure));
    var rejected = pure;
    rejected.name = "wasi:cli/environment@0.2.0";
    try std.testing.expect(!try isTypeOnlyImport(rejected));
    rejected = pure;
    rejected.item.instance = &.{};
    try std.testing.expect(!try isTypeOnlyImport(rejected));
    rejected.item.instance = &.{ integer, .{
        .name = "run",
        .item = .{ .function = .{ .params = &.{} } },
    } };
    try std.testing.expect(!try isTypeOnlyImport(rejected));
    rejected.item.instance = &.{.{ .name = "nested", .item = .{ .value_type = .{
        .record = &.{.{ .name = "value", .ty = .{ .option = &.own_resource } }},
    } } }};
    try std.testing.expect(!try isTypeOnlyImport(rejected));
    rejected.name = "bad\x00name";
    try std.testing.expectError(error.WitInvalid, isTypeOnlyImport(rejected));
}
