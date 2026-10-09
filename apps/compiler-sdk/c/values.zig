//! Typed value and binding construction uses context-owned immutable objects.
const std = @import("std");
const ctx = @import("context.zig");
const c = ctx.c;
const Value = ctx.program.value.Value;
const Binding = ctx.program.model.Binding;

pub export fn nbc2_value(
    handle: ?*c.Handle,
    desc: ?*const c.Value,
    out: ?*c.Object,
) callconv(.c) i32 {
    if (out) |destination| destination.* = .{};
    const self = ctx.context(handle) orelse return -1;
    const destination = out orelse return self.fail(error.InvalidArgument);
    destination.* = .{};
    const item = convert(self, (desc orelse return self.fail(error.InvalidArgument)).*) catch |err|
        return self.fail(err);
    ctx.program.value.validate(item, .{}) catch |err| return self.fail(err);
    destination.* = self.put(.{ .value = item }) catch |err| return self.fail(err);
    return self.success();
}

pub export fn nbc2_binding(
    handle: ?*c.Handle,
    desc: ?*const c.Binding,
    out: ?*c.Object,
) callconv(.c) i32 {
    if (out) |destination| destination.* = .{};
    const self = ctx.context(handle) orelse return -1;
    const destination = out orelse return self.fail(error.InvalidArgument);
    destination.* = .{};
    const item = binding(self, (desc orelse return self.fail(error.InvalidArgument)).*) catch |err|
        return self.fail(err);
    destination.* = self.put(.{ .binding = item }) catch |err| return self.fail(err);
    return self.success();
}

fn convert(self: *ctx.Context, input: c.Value) ctx.Error!Value {
    return switch (input.tag) {
        1 => .{ .boolean = try boolean(input.flags) },
        2 => .{ .uint8 = try integer(u8, input.unsigned_value) },
        3 => .{ .uint16 = try integer(u16, input.unsigned_value) },
        4 => .{ .uint32 = try integer(u32, input.unsigned_value) },
        5 => .{ .uint64 = input.unsigned_value },
        6 => .{ .sint8 = try integer(i8, input.signed_value) },
        7 => .{ .sint16 = try integer(i16, input.signed_value) },
        8 => .{ .sint32 = try integer(i32, input.signed_value) },
        9 => .{ .sint64 = input.signed_value },
        10 => .{ .float32 = @floatCast(input.number) },
        11 => .{ .float64 = input.number },
        12 => .{ .character = try integer(u32, input.unsigned_value) },
        13 => .{ .text = try ctx.view(input.text) },
        14 => .{ .bytes = try ctx.view(input.text) },
        15 => .{ .list = try ctx.values(self, input.items) },
        16 => .{ .tuple = try ctx.values(self, input.items) },
        17 => .{ .record = try record(self, input.fields) },
        18 => .{ .variant = .{
            .name = try ctx.view(input.text),
            .payload = try payload(self, input.payload),
        } },
        19 => .{ .enumeration = try ctx.view(input.text) },
        20 => .{ .option = try payload(self, input.payload) },
        21 => .{ .result = .{
            .success = try boolean(input.flags),
            .payload = try payload(self, input.payload),
        } },
        22 => .{ .flags = try ctx.names(self, input.names) },
        else => error.InvalidArgument,
    };
}

fn boolean(value: u32) ctx.Error!bool {
    return switch (value) {
        0 => false,
        1 => true,
        else => error.InvalidArgument,
    };
}
fn integer(comptime T: type, value: anytype) ctx.Error!T {
    return std.math.cast(T, value) orelse error.InvalidArgument;
}
fn payload(self: *ctx.Context, object: c.Object) ctx.Error!?*const Value {
    if (object.owner == null and object.kind == 0 and object.index == 0) return null;
    const value = try self.value(object);
    const box = try self.arena.allocator().create(Value);
    box.* = value;
    return box;
}
fn record(self: *ctx.Context, input: c.Span(c.Named)) ctx.Error![]const ctx.program.value.Field {
    const source = try ctx.items(c.Named, input);
    const fields = try self.arena.allocator().alloc(ctx.program.value.Field, source.len);
    for (source, fields) |item, *field| {
        field.* = .{ .name = try ctx.view(item.name), .value = try self.value(item.object) };
    }
    return fields;
}
fn binding(self: *ctx.Context, input: c.Binding) ctx.Error!Binding {
    return switch (input.tag) {
        1 => .{ .literal = try self.value(input.payload) },
        2 => .{ .input = try ctx.view(input.reference) },
        3 => .{ .node_result = .{
            .id = try ctx.view(input.reference),
            .fields = try ctx.names(self, input.projection),
        } },
        4 => .{ .observation = .{
            .id = try ctx.view(input.reference),
            .fields = try ctx.names(self, input.projection),
        } },
        5 => .previous_state,
        6 => .{ .record = try bindingRecord(self, input.fields) },
        7 => .{ .list = try ctx.bindings(self, input.items) },
        8 => .{ .tuple = try ctx.bindings(self, input.items) },
        9 => blk: {
            const value = try self.binding(input.payload);
            const box = try self.arena.allocator().create(Binding);
            box.* = value;
            break :blk .{ .some = box };
        },
        else => error.InvalidArgument,
    };
}
fn bindingRecord(
    self: *ctx.Context,
    input: c.Span(c.Named),
) ctx.Error![]const ctx.program.model.BindingField {
    const source = try ctx.items(c.Named, input);
    const fields = try self.arena.allocator().alloc(ctx.program.model.BindingField, source.len);
    for (source, fields) |item, *field| {
        field.* = .{ .name = try ctx.view(item.name), .binding = try self.binding(item.object) };
    }
    return fields;
}
