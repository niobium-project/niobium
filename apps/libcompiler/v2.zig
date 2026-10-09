//! Authoring ABI v2. Every operation delegates to the same native author Builder.
const std = @import("std");
const compiler = @import("compiler");
const ctx = @import("v2_context.zig");
pub const c = ctx.c;
comptime {
    _ = @import("v2_values.zig");
    _ = @import("v2_entries.zig");
}

pub export fn nbc2_create(
    abi: u32,
    id: c.View,
    release: u64,
    version: u32,
    profile: ?*const c.Profile,
    out: ?*?*c.Handle,
) callconv(.c) i32 {
    const destination = out orelse return -1;
    destination.* = null;
    if (abi != 2) return -1;
    const spec = profile orelse return -1;
    const target_text = ctx.view(spec.target) catch return -1;
    const target = std.meta.stringToEnum(ctx.program.profile.Target, target_text) orelse return -1;
    const self = ctx.allocator.create(ctx.Context) catch return -3;
    self.arena = .init(ctx.allocator);
    self.objects = .empty;
    self.last_error = "";
    self.builder = create(self, id, release, version, spec.*, target) catch |err| {
        self.arena.deinit();
        ctx.allocator.destroy(self);
        return ctx.status(err);
    };
    destination.* = @ptrCast(self);
    return 0;
}
fn create(
    self: *ctx.Context,
    id: c.View,
    release: u64,
    version: u32,
    profile: c.Profile,
    target: ctx.program.profile.Target,
) ctx.Error!compiler.author.Builder {
    return compiler.author.Builder.init(
        self.arena.allocator(),
        try ctx.view(id),
        release,
        version,
        .{
            .id = try ctx.view(profile.id),
            .target = target,
            .primitives = try ctx.requirements(self, profile.primitives),
        },
    );
}
pub export fn nbc2_destroy(handle: ?*c.Handle) callconv(.c) void {
    const self = ctx.context(handle) orelse return;
    self.arena.deinit();
    ctx.allocator.destroy(self);
}
pub export fn nbc2_emit(handle: ?*c.Handle, out: ?*c.Buffer) callconv(.c) i32 {
    if (out) |destination| destination.* = .{};
    const self = ctx.context(handle) orelse return -1;
    const destination = out orelse return self.fail(error.InvalidArgument);
    destination.* = .{};
    const bytes = self.builder.emit() catch |err| return self.fail(err);
    const owned = ctx.allocator.dupe(u8, bytes) catch |err| return self.fail(err);
    destination.* = .{ .data = owned.ptr, .len = owned.len };
    return self.success();
}
pub export fn nbc2_location(
    handle: ?*c.Handle,
    object: c.View,
    file: c.View,
    line: u32,
    column: u32,
) callconv(.c) i32 {
    const self = ctx.context(handle) orelse return -1;
    const key = ctx.view(object) catch |err| return self.fail(err);
    const path = ctx.view(file) catch |err| return self.fail(err);
    self.builder.location(key, .{ .file = path, .line = line, .column = column }) catch |err|
        return self.fail(err);
    return self.success();
}
pub export fn nbc2_emit_source_map(handle: ?*c.Handle, out: ?*c.Buffer) callconv(.c) i32 {
    if (out) |destination| destination.* = .{};
    const self = ctx.context(handle) orelse return -1;
    const destination = out orelse return self.fail(error.InvalidArgument);
    destination.* = .{};
    const bytes = self.builder.emitSourceMap() catch |err| return self.fail(err);
    const owned = ctx.allocator.dupe(u8, bytes) catch |err| return self.fail(err);
    destination.* = .{ .data = owned.ptr, .len = owned.len };
    return self.success();
}
pub export fn nbc2_buffer_free(out: ?*c.Buffer) callconv(.c) void {
    const value = out orelse return;
    if (value.data) |data| ctx.allocator.free(data[0..value.len]);
    value.* = .{};
}
pub export fn nbc2_last_error(handle: ?*c.Handle, out: ?*c.View) callconv(.c) i32 {
    if (out) |destination| destination.* = .{};
    const self = ctx.context(handle) orelse return -1;
    const destination = out orelse return -1;
    destination.* = .{ .data = self.last_error.ptr, .len = self.last_error.len };
    return 0;
}

test {
    _ = @import("v2_test.zig");
}
