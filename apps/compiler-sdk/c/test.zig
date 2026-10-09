//! Cross-context handles and normalized native/C models exercise the actual exported API.
const std = @import("std");
const compiler = @import("compiler");
const api = @import("root.zig");
const values = @import("values.zig");
const entries = @import("entries.zig");
const c = api.c;
fn view(bytes: []const u8) c.View {
    return .{ .data = bytes.ptr, .len = bytes.len };
}
fn create() !*c.Handle {
    const profile: c.Profile = .{
        .id = view("niobium.user"),
        .target = view("aarch64-macos"),
        .primitives = .{},
    };
    var handle: ?*c.Handle = null;
    try std.testing.expectEqual(
        @as(i32, 0),
        api.nbc2_create(2, view("reference"), 1, 1, &profile, &handle),
    );
    return handle.?;
}
test "N2-AUTH-02: full-width values and cross-context objects use the shared builder" {
    const a = try create();
    defer api.nbc2_destroy(a);
    const b = try create();
    defer api.nbc2_destroy(b);
    var object: c.Object = .{};
    try std.testing.expectEqual(@as(i32, 0), values.nbc2_value(a, &.{
        .tag = 5,
        .unsigned_value = std.math.maxInt(u64),
    }, &object));
    try std.testing.expectEqual(@as(i32, -1), entries.nbc2_input(b, view("count"), object));
    try std.testing.expectEqual(@as(i32, 0), entries.nbc2_input(a, view("count"), object));
    var buffer: c.Buffer = .{};
    defer api.nbc2_buffer_free(&buffer);
    try std.testing.expectEqual(@as(i32, 0), api.nbc2_emit(a, &buffer));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var native = try compiler.author.Builder.init(arena.allocator(), "reference", 1, 1, .{
        .id = "niobium.user",
        .target = .@"aarch64-macos",
        .primitives = &.{},
    });
    try native.input(.{ .id = "count", .default = .{ .uint64 = std.math.maxInt(u64) } });
    try std.testing.expectEqualStrings(try native.emit(), buffer.data.?[0..buffer.len]);
}
test "N2-AUTH-02: descriptors reject unknown tags and bounds and buffers outlive builders" {
    const handle = try create();
    var value: c.Object = .{};
    try std.testing.expectEqual(@as(i32, -1), values.nbc2_value(handle, &.{ .tag = 99 }, &value));
    try std.testing.expectEqual(@as(i32, -1), values.nbc2_value(handle, &.{
        .tag = 2,
        .unsigned_value = 256,
    }, &value));
    try std.testing.expectEqual(@as(i32, 0), values.nbc2_value(handle, &.{
        .tag = 13,
        .text = view("retained"),
    }, &value));
    try std.testing.expectEqual(@as(i32, 0), entries.nbc2_input(handle, view("label"), value));
    var buffer: c.Buffer = .{};
    try std.testing.expectEqual(@as(i32, 0), api.nbc2_emit(handle, &buffer));
    api.nbc2_destroy(handle);
    try std.testing.expect(std.mem.indexOf(u8, buffer.data.?[0..buffer.len], "retained") != null);
    api.nbc2_buffer_free(&buffer);
    try std.testing.expect(buffer.data == null);
    api.nbc2_buffer_free(&buffer);
}

test "N2-AUTH-02: every declared value and aggregate binding constructor is reachable" {
    const handle = try create();
    defer api.nbc2_destroy(handle);
    var first: c.Object = .{};
    for (1..23) |tag| {
        var object: c.Object = .{};
        const desc: c.Value = .{
            .tag = std.math.cast(u32, tag) orelse return error.TestUnexpectedResult,
            .text = view("case"),
        };
        try std.testing.expectEqual(@as(i32, 0), values.nbc2_value(handle, &desc, &object));
        if (tag == 1) first = object;
    }
    var literal: c.Object = .{};
    try std.testing.expectEqual(@as(i32, 0), values.nbc2_binding(handle, &.{
        .tag = 1,
        .payload = first,
    }, &literal));
    const objects = [_]c.Object{literal};
    const fields = [_]c.Named{.{ .name = view("entry"), .object = literal }};
    for (2..10) |tag| {
        var object: c.Object = .{};
        try std.testing.expectEqual(@as(i32, 0), values.nbc2_binding(handle, &.{
            .tag = std.math.cast(u32, tag) orelse return error.TestUnexpectedResult,
            .reference = view("source"),
            .payload = literal,
            .items = .{ .data = &objects, .len = objects.len },
            .fields = .{ .data = &fields, .len = fields.len },
        }, &object));
    }
    var invalid: c.Object = .{};
    try std.testing.expectEqual(@as(i32, -2), values.nbc2_value(handle, &.{
        .tag = 11,
        .number = std.math.nan(f64),
    }, &invalid));
    try std.testing.expectEqual(@as(i32, -1), values.nbc2_binding(handle, &.{
        .tag = 1,
        .payload = literal,
    }, &invalid));
}

test "N2-AUTH-02: source sidecar is copied and independent of normalized model identity" {
    const handle = try create();
    defer api.nbc2_destroy(handle);
    var model_before: c.Buffer = .{};
    defer api.nbc2_buffer_free(&model_before);
    try std.testing.expectEqual(@as(i32, 0), api.nbc2_emit(handle, &model_before));
    try std.testing.expectEqual(@as(i32, 0), api.nbc2_location(
        handle,
        view("product:reference"),
        view("author.c"),
        12,
        3,
    ));
    var sidecar: c.Buffer = .{};
    defer api.nbc2_buffer_free(&sidecar);
    try std.testing.expectEqual(@as(i32, 0), api.nbc2_emit_source_map(handle, &sidecar));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const decoded = try compiler.pipeline.source_map.decode(
        arena.allocator(),
        sidecar.data.?[0..sidecar.len],
    );
    try std.testing.expectEqualStrings("author.c", decoded.locations[0].source.file);
    try std.testing.expectEqual(@as(u32, 12), decoded.locations[0].source.line);
    var model_after: c.Buffer = .{};
    defer api.nbc2_buffer_free(&model_after);
    try std.testing.expectEqual(@as(i32, 0), api.nbc2_emit(handle, &model_after));
    try std.testing.expectEqualStrings(
        model_before.data.?[0..model_before.len],
        model_after.data.?[0..model_after.len],
    );
    try std.testing.expectEqual(@as(i32, -2), api.nbc2_location(
        handle,
        view("unqualified"),
        view("author.c"),
        12,
        3,
    ));
}

test "N2-AUTH-02: invalid-context calls clear output descriptors" {
    var value: c.Object = .{ .index = 42, .kind = 99 };
    try std.testing.expectEqual(@as(i32, -1), values.nbc2_value(null, &.{ .tag = 1 }, &value));
    try std.testing.expectEqual(@as(u32, 0), value.kind);
    var buffer: c.Buffer = view("borrowed sentinel");
    try std.testing.expectEqual(@as(i32, -1), api.nbc2_emit_source_map(null, &buffer));
    try std.testing.expect(buffer.data == null);
    try std.testing.expectEqual(@as(usize, 0), buffer.len);
}
