//! Each invocation isolates engine traps and allocator exhaustion from the caller.
const std = @import("std");
const engine = @import("component_engine");
const c = engine.c;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.Usage;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[1],
        init.gpa,
        .limited(4 << 20),
    );
    defer init.gpa.free(bytes);
    var host: Host = .{};
    var config = limits;
    if (std.mem.eql(u8, args[2], "type-limit")) config.types = 1;
    if (std.mem.eql(u8, args[2], "depth-limit")) config.depth = 2;
    var session = try engine.Session.load(bytes, config);
    defer session.deinit();
    if (std.mem.eql(u8, args[2], "typed")) try @import("introspection.zig").check(&session);
    try session.addHost(.{
        .interface = "niobium:qualification/host@0.1.0",
        .function = "fact",
    }, fact, &host);
    try session.instantiate(&.{"niobium:qualification/host@0.1.0"});
    try exercise(&session, &host, args[2]);
    const line = try init.arena.allocator().print(
        "PASS {s} host_calls={d} allocation_peak={d}\n",
        .{ args[2], host.calls, c.nb_component_allocation_peak() },
    );
    try std.Io.File.stdout().writeStreamingAll(init.io, line);
}

fn exercise(session: *engine.Session, host: *Host, action: []const u8) !void {
    if (std.mem.eql(u8, action, "typed")) {
        try resources(session);
        // A failed canonical call poisons the instance; the rejection is the last call.
        try typed(session);
        try std.testing.expectEqual(@as(u32, 1), host.calls);
    } else if (std.mem.eql(u8, action, "fuel")) {
        try std.testing.expectError(error.Guest, call(session, "burn", &.{}, &.{}));
        var remaining: u64 = 1;
        try engine.checked(c.wasmtime_context_get_fuel(
            c.wasmtime_store_context(session.store),
            &remaining,
        ));
        try std.testing.expectEqual(@as(u64, 0), remaining);
    } else if (std.mem.eql(u8, action, "memory")) {
        var result: [1]c.Val = undefined;
        try call(session, "allocate", &.{integer(64 << 20)}, &result);
        defer c.wasmtime_component_val_delete(&result[0]);
        try std.testing.expectEqual(std.math.maxInt(u32), result[0].of.u32);
    } else if (std.mem.eql(u8, action, "output")) {
        var result: [1]c.Val = undefined;
        try call(session, "output", &.{integer(65537)}, &result);
        defer c.wasmtime_component_val_delete(&result[0]);
        if (result[0].of.string.size > 65536) return error.OutputLimit;
        return error.ExpectedOutputLimit;
    } else if (std.mem.eql(u8, action, "amplification")) {
        c.nb_component_allocation_limit(128 << 10);
        var result: [1]c.Val = undefined;
        try call(session, "amplify", &.{integer(65536)}, &result);
        c.wasmtime_component_val_delete(&result[0]);
        return error.ExpectedAllocationLimit;
    } else if (std.mem.eql(u8, action, "host-calls")) {
        try std.testing.expectError(error.Guest, call(session, "many", &.{integer(1025)}, &.{}));
        try std.testing.expectEqual(@as(u32, 1024), host.calls);
    } else if (std.mem.eql(u8, action, "instantiate")) {
        try std.testing.expectEqual(@as(u32, 0), host.calls);
    } else return error.Usage;
}

fn typed(session: *engine.Session) !void {
    var values = [_]c.Val{ integer(3), integer(7), integer(11) };
    var enabled: c.Val = .{ .kind = c.bool_kind, .of = .{ .boolean = true } };
    var fields = [_]c.Field{
        .{ .name = text("name"), .val = .{ .kind = c.string_kind, .of = .{
            .string = text("工具链 café"),
        } } },
        .{ .name = text("values"), .val = .{ .kind = c.list_kind, .of = .{
            .list = .{ .size = values.len, .data = &values },
        } } },
        .{ .name = text("enabled"), .val = .{ .kind = c.option_kind, .of = .{
            .option = &enabled,
        } } },
    };
    const input: c.Val = .{ .kind = c.record_kind, .of = .{
        .record = .{ .size = fields.len, .data = &fields },
    } };
    var result: [1]c.Val = undefined;
    try call(session, "evaluate", &.{input}, &result);
    defer c.wasmtime_component_val_delete(&result[0]);
    try std.testing.expectEqual(c.result_kind, result[0].kind);
    try std.testing.expect(result[0].of.result.is_ok);
    const response = result[0].of.result.val orelse return error.MissingValue;
    try std.testing.expectEqual(@as(usize, 2), response.of.record.size);
    const output = response.of.record.data orelse return error.MissingValue;
    const name = output[0].val.of.string;
    try std.testing.expectEqualStrings("qualified-host", name.data.?[0..name.size]);
    try std.testing.expectEqual(@as(u64, 21), output[1].val.of.u64);
    enabled.of.boolean = false;
    var rejected: [1]c.Val = undefined;
    try call(session, "evaluate", &.{input}, &rejected);
    defer c.wasmtime_component_val_delete(&rejected[0]);
    try std.testing.expect(!rejected[0].of.result.is_ok);
    const failure = rejected[0].of.result.val orelse return error.MissingValue;
    const message = failure.of.variant.val orelse return error.MissingValue;
    const string = message.of.string;
    try std.testing.expectEqualStrings("disabled", string.data.?[0..string.size]);
    fields[1].val = .{ .kind = c.bool_kind, .of = .{ .boolean = false } };
    var invalid: [1]c.Val = undefined;
    try std.testing.expectError(error.Guest, call(session, "evaluate", &.{input}, &invalid));
}

fn resources(session: *engine.Session) !void {
    var created: [1]c.Val = undefined;
    try call(session, "[constructor]counter", &.{integer(42)}, &created);
    defer c.wasmtime_component_val_delete(&created[0]);
    try std.testing.expectEqual(c.resource_kind, created[0].kind);
    var read: [1]c.Val = undefined;
    try call(session, "[method]counter.value", &created, &read);
    defer c.wasmtime_component_val_delete(&read[0]);
    try std.testing.expectEqual(@as(u32, 42), read[0].of.u32);
    const resource = created[0].of.resource orelse return error.MissingValue;
    const context = c.wasmtime_store_context(session.store);
    try engine.checked(c.wasmtime_component_resource_any_drop(context, resource));
    try std.testing.expectError(error.Guest, engine.checked(
        c.wasmtime_component_resource_any_drop(context, resource),
    ));
}

fn integer(value: u32) c.Val {
    return .{ .kind = c.u32_kind, .of = .{ .u32 = value } };
}

fn text(value: []const u8) c.Bytes {
    return .{ .size = value.len, .data = @constCast(value.ptr) };
}

const limits: engine.Limits = .{
    .component_bytes = 4 << 20,
    .modules = 64,
    .types = 4096,
    .depth = 32,
    .memory_bytes = 32 << 20,
    .memories = 1,
    .table_elements = 4096,
    .instructions = 1_000_000,
    .stack_bytes = 256 << 10,
    .allocation_bytes = 128 << 20,
};
const Host = struct { calls: u32 = 0, fact: []const u8 = "qualified-host" };

fn fact(
    raw: ?*anyopaque,
    _: *c.Context,
    _: *const c.FuncType,
    _: ?[*]c.Val,
    args: usize,
    results: ?[*]c.Val,
    count: usize,
) callconv(.c) ?*c.Error {
    const pointer = raw orelse return c.wasmtime_error_new("missing host");
    const host: *Host = @ptrCast(@alignCast(pointer));
    if (args != 0 or count != 1) return c.wasmtime_error_new("host signature mismatch");
    if (host.calls >= 1024) return c.wasmtime_error_new("host call budget exhausted");
    host.calls += 1;
    const out = results orelse return c.wasmtime_error_new("missing result");
    out[0].kind = c.string_kind;
    c.wasm_byte_vec_new(&out[0].of.string, host.fact.len, host.fact.ptr);
    return null;
}

fn call(
    session: *engine.Session,
    name: []const u8,
    args: []const c.Val,
    out: []c.Val,
) engine.Error!void {
    return session.call(.{
        .interface = "niobium:qualification/guest@0.1.0",
        .function = name,
    }, args, out);
}
