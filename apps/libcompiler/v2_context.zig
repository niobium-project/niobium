//! Ownership and bounded conversion shared by the version-two C entry points.
const std = @import("std");
const compiler = @import("compiler");
const contracts = @import("contracts");
pub const c = @import("v2_types.zig");
pub const program = compiler.program;
pub const Error = compiler.author.Error || error{InvalidArgument};
pub const allocator = if (@import("builtin").is_test)
    std.testing.allocator
else
    std.heap.smp_allocator;
const Item = union(enum) { value: program.value.Value, binding: program.model.Binding };
pub const Context = struct {
    arena: std.heap.ArenaAllocator,
    builder: compiler.author.Builder,
    objects: std.ArrayList(Item) = .empty,
    last_error: []const u8 = "",

    pub fn fail(self: *Context, err: Error) i32 {
        self.last_error = @errorName(err);
        return status(err);
    }
    pub fn success(self: *Context) i32 {
        self.last_error = "";
        return 0;
    }
    pub fn value(self: *Context, object: c.Object) Error!program.value.Value {
        return switch (try self.item(object, 1)) {
            .value => |v| v,
            else => error.InvalidArgument,
        };
    }
    pub fn binding(self: *Context, object: c.Object) Error!program.model.Binding {
        return switch (try self.item(object, 2)) {
            .binding => |v| v,
            else => error.InvalidArgument,
        };
    }
    fn item(self: *Context, object: c.Object, kind: u32) Error!Item {
        if (object.owner != @as(*const c.Handle, @ptrCast(self)) or object.kind != kind or
            object.index >= self.objects.items.len) return error.InvalidArgument;
        return self.objects.items[object.index];
    }
    pub fn put(self: *Context, value_: Item) Error!c.Object {
        if (self.objects.items.len >= contracts.limits.default.component_types)
            return error.AuthoringLimit;
        const item_copy: Item = switch (value_) {
            .value => |v| .{ .value = try self.builder.snapshot(program.value.Value, v) },
            .binding => |v| .{ .binding = try self.builder.snapshot(program.model.Binding, v) },
        };
        const index = std.math.cast(u32, self.objects.items.len) orelse return error.AuthoringLimit;
        try self.objects.append(self.arena.allocator(), item_copy);
        return .{ .owner = @ptrCast(self), .index = index, .kind = if (value_ == .value) 1 else 2 };
    }
};
pub fn context(handle: ?*c.Handle) ?*Context {
    return @ptrCast(@alignCast(handle orelse return null));
}
pub fn status(err: Error) i32 {
    return switch (err) {
        error.InvalidArgument => -1,
        error.OutOfMemory => -3,
        else => -2,
    };
}
pub fn view(input: c.View) Error![]const u8 {
    if (input.len > contracts.limits.default.program_bytes) return error.InvalidArgument;
    return span(u8, input.data, input.len, contracts.limits.default.program_bytes);
}
pub fn span(comptime T: type, pointer: ?[*]const T, len: usize, maximum: usize) Error![]const T {
    if (len > maximum) return error.InvalidArgument;
    if (len == 0) return &.{};
    return (pointer orelse return error.InvalidArgument)[0..len];
}
pub fn items(comptime T: type, input: c.Span(T)) Error![]const T {
    return span(T, input.data, input.len, contracts.limits.default.component_types);
}
pub fn names(self: *Context, input: c.Span(c.View)) Error![]const []const u8 {
    const source = try items(c.View, input);
    const result = try self.arena.allocator().alloc([]const u8, source.len);
    for (source, result) |item_, *out| out.* = try view(item_);
    return result;
}
pub fn requirements(
    self: *Context,
    input: c.Span(c.Requirement),
) Error![]program.profile.Requirement {
    const source = try items(c.Requirement, input);
    const result = try self.arena.allocator().alloc(program.profile.Requirement, source.len);
    for (source, result) |item_, *out| out.* = .{
        .id = try view(item_.id),
        .version = item_.version,
    };
    return result;
}
pub fn values(self: *Context, input: c.Span(c.Object)) Error![]const program.value.Value {
    const source = try items(c.Object, input);
    const result = try self.arena.allocator().alloc(program.value.Value, source.len);
    for (source, result) |item_, *out| out.* = try self.value(item_);
    return result;
}
pub fn bindings(self: *Context, input: c.Span(c.Object)) Error![]const program.model.Binding {
    const source = try items(c.Object, input);
    const result = try self.arena.allocator().alloc(program.model.Binding, source.len);
    for (source, result) |item_, *out| out.* = try self.binding(item_);
    return result;
}
