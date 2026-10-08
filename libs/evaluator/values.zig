//! Conversion from validated WIT values into host-owned content and access contracts.
const std = @import("std");
const program = @import("program");
const contracts = @import("contracts");
const content = @import("content");
const access = @import("access_policy");
const Value = program.value.Value;
pub const Error = program.value.Error || content.Error || access.Error || error{GuestRejected};

pub fn field(value: Value, name: []const u8) Error!Value {
    if (value != .record or value.record.len > contracts.limits.default.program_items)
        return error.ValueInvalid;
    for (value.record) |item| {
        if (std.mem.eql(u8, item.name, name)) return item.value;
    }
    return error.ValueInvalid;
}

pub fn string(value: Value) Error![]const u8 {
    return if (value == .text) value.text else error.ValueInvalid;
}

pub fn unwrap(value: Value) Error!Value {
    if (value != .result) return value;
    if (!value.result.success) return error.GuestRejected;
    return (value.result.payload orelse return error.ValueInvalid).*;
}

pub fn byteList(arena: std.mem.Allocator, value: Value) Error![]const u8 {
    if (value == .bytes) return value.bytes;
    if (value != .list or value.list.len > contracts.limits.default.component_output_bytes)
        return error.ValueInvalid;
    const bytes = try arena.alloc(u8, value.list.len);
    for (value.list, bytes) |item, *byte| {
        if (item != .uint8) return error.ValueInvalid;
        byte.* = item.uint8;
    }
    return bytes;
}

pub fn reference(arena: std.mem.Allocator, value: Value) Error!content.ContainerRef {
    const format = try field(value, "format");
    if (format != .enumeration or !std.mem.eql(u8, format.enumeration, "posix-pax-v1"))
        return error.ValueInvalid;
    const bytes = try field(value, "bytes");
    if (bytes != .uint64) return error.ValueInvalid;
    const sha256 = try byteList(arena, try field(value, "sha256"));
    if (sha256.len != 32) return error.ValueInvalid;
    return .{ .sha256 = sha256[0..32].*, .bytes = bytes.uint64 };
}

pub fn policy(value: Value, expected: access.Kind) Error!access.Policy {
    const schema = try field(value, "schema");
    const kind = try field(value, "kind");
    if (schema != .uint32 or kind != .enumeration or
        !std.mem.eql(u8, @tagName(expected), kind.enumeration)) return error.ValueInvalid;
    const result: access.Policy = .{
        .schema = schema.uint32,
        .kind = expected,
        .owner = try rights(try field(value, "owner")),
        .everyone = try rights(try field(value, "everyone")),
    };
    try access.validate(result);
    return result;
}

fn rights(value: Value) Error!access.Rights {
    const read = try field(value, "read");
    const write = try field(value, "write");
    const execute = try field(value, "execute");
    if (read != .boolean or write != .boolean or execute != .boolean) return error.ValueInvalid;
    return .{ .read = read.boolean, .write = write.boolean, .execute = execute.boolean };
}

pub fn tree(arena: std.mem.Allocator, value: Value) Error!content.Tree {
    if (value != .list or value.list.len > contracts.limits.default.component_types)
        return error.ValueLimit;
    const entries = try arena.alloc(content.Entry, value.list.len);
    for (value.list, entries) |item, *entry| {
        const mode = try field(item, "mode");
        const kind = try field(item, "kind");
        if (mode != .uint16 or kind != .variant) return error.ValueInvalid;
        entry.* = .{ .path = try string(try field(item, "path")), .mode = mode.uint16 };
        if (std.mem.eql(u8, kind.variant.name, "directory")) {
            if (kind.variant.payload != null) return error.ValueInvalid;
            entry.kind = .directory;
        } else if (std.mem.eql(u8, kind.variant.name, "file")) {
            const payload = (kind.variant.payload orelse return error.ValueInvalid).*;
            const bytes = try byteList(arena, payload);
            entry.body = content.Body.bytes(bytes);
        } else if (std.mem.eql(u8, kind.variant.name, "symlink")) {
            entry.kind = .symlink;
            entry.link_target = try string((kind.variant.payload orelse
                return error.ValueInvalid).*);
        } else return error.ValueInvalid;
    }
    return content.fromEntries(arena, entries, .{});
}

test "N2-EVAL-02: generated trees cannot forge paths or malformed permissions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const data: Value = .{ .bytes = "owned" };
    const entry: Value = .{ .record = &.{
        .{ .name = "path", .value = .{ .text = "../escape" } },
        .{ .name = "mode", .value = .{ .uint16 = 0o600 } },
        .{ .name = "kind", .value = .{ .variant = .{ .name = "file", .payload = &data } } },
    } };
    try std.testing.expectError(error.ContentInvalid, tree(
        arena.allocator(),
        .{ .list = &.{entry} },
    ));
}
