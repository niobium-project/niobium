//! Product entries expose typed descriptors and use shared model validation.
const std = @import("std");
const compiler = @import("compiler");
const ctx = @import("context.zig");
const c = ctx.c;
const model = ctx.program.model;

pub export fn nbc2_input(handle: ?*c.Handle, id: c.View, object: c.Object) callconv(.c) i32 {
    const self = ctx.context(handle) orelse return -1;
    const entry: model.Input = .{
        .id = ctx.view(id) catch |err| return self.fail(err),
        .default = self.value(object) catch |err| return self.fail(err),
    };
    self.builder.input(entry) catch |err| return self.fail(err);
    return self.success();
}
pub export fn nbc2_library_add(handle: ?*c.Handle, desc: ?*const c.Library) callconv(.c) i32 {
    return add(c.Library, "library", handle, desc, library);
}
pub export fn nbc2_container_add(handle: ?*c.Handle, desc: ?*const c.Container) callconv(.c) i32 {
    return add(c.Container, "container", handle, desc, container);
}
pub export fn nbc2_grant_add(handle: ?*c.Handle, desc: ?*const c.Grant) callconv(.c) i32 {
    return add(c.Grant, "grant", handle, desc, grant);
}
pub export fn nbc2_observe(handle: ?*c.Handle, desc: ?*const c.Observation) callconv(.c) i32 {
    return add(c.Observation, "observe", handle, desc, observation);
}
pub export fn nbc2_call_add(handle: ?*c.Handle, desc: ?*const c.Call) callconv(.c) i32 {
    return add(c.Call, "call", handle, desc, call);
}
pub export fn nbc2_root(handle: ?*c.Handle, id: c.View, scope: u32) callconv(.c) i32 {
    const self = ctx.context(handle) orelse return -1;
    const entry: model.Root = .{
        .id = ctx.view(id) catch |err| return self.fail(err),
        .scope = switch (scope) {
            1 => .user,
            2 => .machine,
            else => return self.fail(error.InvalidArgument),
        },
    };
    self.builder.root(entry) catch |err| return self.fail(err);
    return self.success();
}
pub export fn nbc2_state_root(handle: ?*c.Handle, id: c.View) callconv(.c) i32 {
    const self = ctx.context(handle) orelse return -1;
    const name = ctx.view(id) catch |err| return self.fail(err);
    self.builder.stateRoot(name) catch |err| return self.fail(err);
    return self.success();
}
pub export fn nbc2_upgrade(handle: ?*c.Handle, id: c.View, from: u32, to: u32) callconv(.c) i32 {
    const self = ctx.context(handle) orelse return -1;
    const name = ctx.view(id) catch |err| return self.fail(err);
    self.builder.upgrade(.{ .id = name, .from = from, .to = to }) catch |err| return self.fail(err);
    return self.success();
}
fn add(
    comptime T: type,
    comptime method: []const u8,
    handle: ?*c.Handle,
    desc: ?*const T,
    comptime convert: anytype,
) i32 {
    const self = ctx.context(handle) orelse return -1;
    const input = desc orelse return self.fail(error.InvalidArgument);
    const entry = convert(self, input.*) catch |err| return self.fail(err);
    @field(compiler.author.Builder, method)(&self.builder, entry) catch |err| return self.fail(err);
    return self.success();
}
fn library(self: *ctx.Context, input: c.Library) ctx.Error!model.Library {
    return .{
        .id = try ctx.view(input.id),
        .member = try ctx.view(input.member),
        .sha256 = try ctx.view(input.sha256),
        .bytes = input.bytes,
        .requires = try ctx.requirements(self, input.requires),
    };
}
fn container(_: *ctx.Context, input: c.Container) ctx.Error!model.Container {
    const bytes = try ctx.view(input.sha256);
    if (bytes.len != 32) return error.InvalidArgument;
    return .{
        .id = try ctx.view(input.id),
        .member = try ctx.view(input.member),
        .reference = .{ .sha256 = bytes[0..32].*, .bytes = input.bytes },
    };
}
fn policy(input: c.Policy) ctx.Error!@FieldType(model.Grant, "file_access") {
    const owner = std.math.cast(u3, input.owner) orelse return error.InvalidArgument;
    const everyone = std.math.cast(u3, input.everyone) orelse return error.InvalidArgument;
    return .{
        .kind = switch (input.kind) {
            1 => .file,
            2 => .directory,
            else => return error.InvalidArgument,
        },
        .owner = .fromBits(owner),
        .everyone = .fromBits(everyone),
    };
}
fn grant(_: *ctx.Context, input: c.Grant) ctx.Error!model.Grant {
    return .{
        .id = try ctx.view(input.id),
        .root = try ctx.view(input.root),
        .prefix = try ctx.view(input.prefix),
        .primitive = .{
            .id = try ctx.view(input.primitive.id),
            .version = input.primitive.version,
        },
        .max_entries = input.max_entries,
        .max_bytes = input.max_bytes,
        .file_access = try policy(input.file_access),
        .directory_access = try policy(input.directory_access),
    };
}
fn observation(self: *ctx.Context, input: c.Observation) ctx.Error!model.Observation {
    const owner = try ctx.view(input.grant);
    return .{
        .id = try ctx.view(input.id),
        .function = try ctx.view(input.function),
        .grant = if (owner.len == 0) null else owner,
        .primitive = .{
            .id = try ctx.view(input.primitive.id),
            .version = input.primitive.version,
        },
        .arguments = try ctx.values(self, input.arguments),
    };
}
fn call(self: *ctx.Context, input: c.Call) ctx.Error!model.Call {
    const source = try ctx.items(c.Migration, input.migrations);
    const migrations = try self.arena.allocator().alloc(model.Migration, source.len);
    for (source, migrations) |item, *migration| migration.* = .{
        .id = try ctx.view(item.id),
        .library = try ctx.view(item.library),
        .interface = try ctx.view(item.interface_name),
        .function = try ctx.view(item.function),
        .implementation_sha256 = try ctx.view(item.implementation_sha256),
        .from = item.from_version,
        .to = item.to_version,
    };
    return .{
        .id = try ctx.view(input.id),
        .library = try ctx.view(input.library),
        .interface = try ctx.view(input.interface_name),
        .function = try ctx.view(input.function),
        .arguments = try ctx.bindings(self, input.arguments),
        .grants = try ctx.names(self, input.grants),
        .after = try ctx.names(self, input.after),
        .state_version = input.state_version,
        .migrations = migrations,
        .result_role = switch (input.result_role) {
            0 => .value,
            1 => .plan,
            else => return error.InvalidArgument,
        },
    };
}
