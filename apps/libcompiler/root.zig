//! Authoring C ABI v1. Native and hosted frontends share compiler.Builder semantics.

const std = @import("std");
const compiler = @import("compiler");
const contracts = @import("contracts");
const allocator = if (@import("builtin").is_test) std.testing.allocator else std.heap.smp_allocator;

pub const Handle = opaque {};
pub const View = extern struct { data: ?[*]const u8, len: usize };
pub const Buffer = extern struct { data: ?[*]const u8, len: usize };
const Error = compiler.Error || error{InvalidArgument};
const Context = struct {
    arena: std.heap.ArenaAllocator,
    builder: compiler.Builder,
    last_error: []const u8 = "",

    fn fail(self: *Context, err: Error) i32 {
        self.last_error = @errorName(err);
        return status(err);
    }

    fn success(self: *Context) i32 {
        self.last_error = "";
        return 0;
    }
};

fn status(err: Error) i32 {
    return switch (err) {
        error.InvalidArgument => -1,
        error.OutOfMemory => -3,
        else => -2,
    };
}

fn context(handle: ?*Handle) ?*Context {
    return @ptrCast(@alignCast(handle orelse return null));
}

fn slice(value: View) Error![]const u8 {
    if (value.len > (contracts.Limits{}).program_bytes) return error.InvalidArgument;
    if (value.len == 0) return &.{};
    const pointer = value.data orelse return error.InvalidArgument;
    return pointer[0..value.len];
}

pub export fn nbc_create(
    abi: u32,
    id: View,
    sequence: u64,
    model_version: u32,
    out: ?*?*Handle,
) callconv(.c) i32 {
    const destination = out orelse return -1;
    destination.* = null;
    if (abi != 1) return -1;
    const product_id = slice(id) catch return -1;
    const value = allocator.create(Context) catch return -3;
    value.arena = .init(allocator);
    value.builder = compiler.Builder.init(
        value.arena.allocator(),
        product_id,
        sequence,
        model_version,
    ) catch |err| {
        value.arena.deinit();
        allocator.destroy(value);
        return status(err);
    };
    value.last_error = "";
    destination.* = @ptrCast(value);
    return 0;
}

pub export fn nbc_destroy(handle: ?*Handle) callconv(.c) void {
    const value = context(handle) orelse return;
    value.arena.deinit();
    allocator.destroy(value);
}

const Entry = enum { input, library, asset, resource };

fn add(handle: ?*Handle, id: View, data: View, kind: Entry) i32 {
    const value = context(handle) orelse return -1;
    const name = slice(id) catch |err| return value.fail(err);
    const bytes = slice(data) catch |err| return value.fail(err);
    const result = switch (kind) {
        .input => value.builder.addInput(name, bytes),
        .library => value.builder.addLibrary(name, bytes),
        .asset => value.builder.addAsset(name, bytes),
        .resource => value.builder.addResource(name, bytes),
    };
    result catch |err| return value.fail(err);
    return value.success();
}

pub export fn nbc_add_input(handle: ?*Handle, id: View, data: View) callconv(.c) i32 {
    return add(handle, id, data, .input);
}

pub export fn nbc_add_library(handle: ?*Handle, id: View, data: View) callconv(.c) i32 {
    return add(handle, id, data, .library);
}

pub export fn nbc_add_asset(handle: ?*Handle, id: View, data: View) callconv(.c) i32 {
    return add(handle, id, data, .asset);
}

pub export fn nbc_add_resource(handle: ?*Handle, id: View, data: View) callconv(.c) i32 {
    return add(handle, id, data, .resource);
}

pub export fn nbc_add_instance(
    handle: ?*Handle,
    id: View,
    library: View,
    state_version: u32,
) callconv(.c) i32 {
    const value = context(handle) orelse return -1;
    const name = slice(id) catch |err| return value.fail(err);
    const reference = slice(library) catch |err| return value.fail(err);
    value.builder.addInstance(name, reference, state_version) catch |err| return value.fail(err);
    return value.success();
}

pub export fn nbc_bind(
    handle: ?*Handle,
    instance: View,
    kind: u32,
    reference: View,
) callconv(.c) i32 {
    const value = context(handle) orelse return -1;
    const owner = slice(instance) catch |err| return value.fail(err);
    const target = slice(reference) catch |err| return value.fail(err);
    const binding: compiler.Binding = switch (kind) {
        1 => .input,
        2 => .asset,
        3 => .resource,
        else => return value.fail(error.InvalidArgument),
    };
    value.builder.bind(owner, binding, target) catch |err| return value.fail(err);
    return value.success();
}

pub export fn nbc_add_migration(
    handle: ?*Handle,
    owner: View,
    id: View,
    from: u32,
    to: u32,
) callconv(.c) i32 {
    const value = context(handle) orelse return -1;
    const instance = slice(owner) catch |err| return value.fail(err);
    const name = slice(id) catch |err| return value.fail(err);
    value.builder.addMigration(instance, name, from, to) catch |err| return value.fail(err);
    return value.success();
}

pub export fn nbc_emit(handle: ?*Handle, out: ?*Buffer) callconv(.c) i32 {
    const value = context(handle) orelse return -1;
    const destination = out orelse return value.fail(error.InvalidArgument);
    destination.* = .{ .data = null, .len = 0 };
    const bytes = value.builder.emit() catch |err| return value.fail(err);
    const owned = allocator.dupe(u8, bytes) catch |err| return value.fail(err);
    destination.* = .{ .data = owned.ptr, .len = owned.len };
    return value.success();
}

pub export fn nbc_buffer_free(out: ?*Buffer) callconv(.c) void {
    const buffer = out orelse return;
    if (buffer.data) |pointer| allocator.free(pointer[0..buffer.len]);
    buffer.* = .{ .data = null, .len = 0 };
}

pub export fn nbc_last_error(handle: ?*Handle, out: ?*View) callconv(.c) i32 {
    const value = context(handle) orelse return -1;
    const destination = out orelse return -1;
    destination.* = .{ .data = value.last_error.ptr, .len = value.last_error.len };
    return 0;
}

test "N2-AUTH-01: C ABI rejects invalid inputs and retains error lifetime" {
    var handle: ?*Handle = null;
    const id: View = .{ .data = "example.product", .len = "example.product".len };
    try std.testing.expectEqual(@as(i32, -1), nbc_create(2, id, 1, 1, &handle));
    try std.testing.expect(handle == null);
    try std.testing.expectEqual(@as(i32, 0), nbc_create(1, id, 1, 1, &handle));
    defer nbc_destroy(handle);
    const invalid: View = .{ .data = null, .len = 1 };
    try std.testing.expectEqual(@as(i32, -1), nbc_add_input(handle, id, invalid));
    var message: View = .{ .data = null, .len = 0 };
    try std.testing.expectEqual(@as(i32, 0), nbc_last_error(handle, &message));
    try std.testing.expectEqualStrings("InvalidArgument", message.data.?[0..message.len]);
}

test "N2-AUTH-01: emitted buffer outlives builder and failed additions remain absent" {
    const view = struct {
        fn of(bytes: []const u8) View {
            return .{ .data = bytes.ptr, .len = bytes.len };
        }
    }.of;
    const wasm = "\x00asm\x01\x00\x00\x00" ++
        "\x01\x05\x01\x60\x00\x01\x7f\x03\x02\x01\x00" ++
        "\x05\x04\x01\x01\x01\x01" ++
        "\x07\x17\x02\x06memory\x02\x00\x0anb_plan_v1\x00\x00" ++
        "\x0a\x06\x01\x04\x00\x41\x00\x0b";
    var handle: ?*Handle = null;
    try std.testing.expectEqual(@as(i32, 0), nbc_create(1, view("example.product"), 1, 1, &handle));
    // The buffer deliberately survives the enclosing builder lifetime.
    var output: Buffer = .{ .data = null, .len = 0 };
    defer nbc_buffer_free(&output);
    {
        defer nbc_destroy(handle);
        try std.testing.expectEqual(@as(i32, -2), nbc_add_library(
            handle,
            view("bad"),
            view("bad"),
        ));
        try std.testing.expectEqual(@as(i32, 0), nbc_add_library(
            handle,
            view("library"),
            view(wasm),
        ));
        try std.testing.expectEqual(@as(i32, 0), nbc_add_instance(
            handle,
            view("instance"),
            view("library"),
            1,
        ));
        try std.testing.expectEqual(@as(i32, -1), nbc_bind(
            handle,
            view("instance"),
            9,
            view("bad"),
        ));
        try std.testing.expectEqual(@as(i32, 0), nbc_emit(handle, &output));
    }
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const model = try compiler.program.decode(arena.allocator(), output.data.?[0..output.len]);
    try std.testing.expectEqual(@as(usize, 1), model.libraries.len);
    try std.testing.expectEqualStrings("library", model.libraries[0].id);
    nbc_buffer_free(&output);
    try std.testing.expect(output.data == null);
    try std.testing.expectEqual(@as(usize, 0), output.len);
}
