//! Exact allow-only DACL projection. Native ACL inheritance and arbitrary ACEs are excluded.
const std = @import("std");
const contracts = @import("contracts");
const b = @import("bindings.zig");
const p = @import("access_policy");
const t = @import("types.zig");

const everyone_sid = "\x01\x01\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00";
const read_control: u32 = 0x00020000;
const write_dac: u32 = 0x00040000;
const generic_read: u32 = 0x00120089;
const generic_write: u32 = 0x00120116;
const generic_execute: u32 = 0x001200a0;
const traverse: u32 = 0x20;
const delete_child: u32 = 0x40;

pub fn stat(handle: usize) t.Error!b.Stat {
    var value: b.Stat = undefined; // SAFETY: the bridge fills every field on success.
    try t.status(b.nb_access_stat_handle(handle, &value));
    if (value.volume_flags != 16) return error.AccessUnsupported;
    const filesystem = std.mem.sliceTo(&value.filesystem_name, 0);
    if (!std.mem.eql(u8, filesystem, "NTFS") and !std.mem.eql(u8, filesystem, "ReFS"))
        return error.AccessUnsupported;
    if (value.object_flags & 0x400 != 0) return error.AccessWrongKind;
    if (value.kind == 1 and value.object_flags & 1 != 0) return error.AccessUnsupported;
    if (value.kind == 1 and value.nlink != 1) return error.AccessConflict;
    return value;
}

pub fn parentSafe(handle: usize) t.Error!void {
    const value = try stat(handle);
    if (value.kind != 2) return error.AccessWrongKind;
}

pub fn prepareNew(handle: usize, kind: p.Kind) t.Error!void {
    const value = try stat(handle);
    if (value.kind != @backingInt(kind)) return error.AccessWrongKind;
}

pub fn inspect(arena: std.mem.Allocator, handle: usize) t.Error!t.Observation {
    const value = try stat(handle);
    var owner: t.Owner = .{};
    var owner_length: u32 = 0;
    var length: u32 = 0;
    var control: u32 = 0;
    const buffer = try arena.alignedAlloc(u8, .@"4", (contracts.Limits{}).access_acl_bytes);
    const capacity = std.math.cast(u32, buffer.len) orelse return error.AccessLimit;
    try t.status(b.nb_access_windows_security(
        handle,
        &owner.bytes,
        owner.bytes.len,
        &owner_length,
        buffer.ptr,
        capacity,
        &length,
        &control,
    ));
    owner.length = std.math.cast(u8, owner_length) orelse return error.AccessLimit;
    if (length > buffer.len or owner.length > owner.bytes.len) return error.AccessLimit;
    if (control != 1) return error.AccessConflict;
    try validateSid(owner.bytes[0..owner.length]);
    const kind: p.Kind = if (value.kind == 1) .file else .directory;
    const native = try arena.dupe(u8, buffer[0..length]);
    return .{
        .os = .windows,
        .identity = .{
            .volume = value.volume,
            .inode_low = value.inode_low,
            .inode_high = value.inode_high,
        },
        .owner = owner,
        .policy = try parseAcl(native, kind, owner),
        .native = native,
    };
}

pub fn validateObservation(value: t.Observation) t.Error!void {
    if (value.os != .windows or value.owner.length > value.owner.bytes.len)
        return error.AccessReceiptInvalid;
    try validateSid(value.owner.bytes[0..value.owner.length]);
    const parsed = try parseAcl(value.native, value.policy.kind, value.owner);
    if (!p.equal(parsed, value.policy)) return error.AccessReceiptInvalid;
}

pub fn acl(owner: t.Owner, value: p.Policy, buffer: []align(4) u8) t.Error![]align(4) u8 {
    if (owner.length > owner.bytes.len) return error.AccessReceiptInvalid;
    try validateSid(owner.bytes[0..owner.length]);
    const other = mask(value.kind, value.everyone, false);
    const size = 8 + 8 + @as(usize, owner.length) + if (other != 0) @as(usize, 20) else 0;
    if (size > buffer.len) return error.AccessLimit;
    const bytes = buffer[0..size];
    @memset(bytes, 0);
    bytes[0] = 2;
    std.mem.writeInt(u16, bytes[2..4], std.math.cast(u16, size) orelse
        return error.AccessLimit, .little);
    std.mem.writeInt(u16, bytes[4..6], if (other != 0) 2 else 1, .little);
    try putAce(bytes[8..], mask(value.kind, value.owner, true), owner.bytes[0..owner.length]);
    if (other != 0) try putAce(bytes[16 + owner.length ..], other, everyone_sid);
    return bytes;
}

pub fn apply(handle: usize, current: t.Observation, target: p.Policy) t.Error!void {
    var buffer: [128]u8 align(4) = undefined; // SAFETY: acl initializes its returned prefix.
    const bytes = try acl(current.owner, target, &buffer);
    const length = std.math.cast(u32, bytes.len) orelse return error.AccessLimit;
    try t.status(b.nb_access_windows_set_acl(handle, bytes.ptr, length, 1));
}

pub fn restore(handle: usize, current: t.Observation, prior: t.Observation) t.Error!void {
    return apply(handle, current, prior.policy);
}

fn mask(kind: p.Kind, rights: p.Rights, owner: bool) u32 {
    var value: u32 = if (owner) read_control | write_dac | 0x00100080 else 0;
    if (rights.read) value |= generic_read;
    if (rights.write) value |= generic_write;
    if (kind == .file) {
        if (rights.execute) value |= generic_execute;
    } else {
        value |= traverse;
        if (rights.write) value |= delete_child;
    }
    return value;
}

fn putAce(bytes: []u8, access: u32, sid: []const u8) t.Error!void {
    std.debug.assert(bytes.len >= 8 + sid.len);
    bytes[0] = 0;
    bytes[1] = 0;
    // SID length is validated against its native ABI ceiling before this helper is called.
    const size = std.math.cast(u16, 8 + sid.len) orelse return error.AccessLimit;
    std.mem.writeInt(u16, bytes[2..4], size, .little);
    std.mem.writeInt(u32, bytes[4..8], access, .little);
    @memcpy(bytes[8..][0..sid.len], sid);
}

fn parseAcl(bytes: []const u8, kind: p.Kind, owner: t.Owner) t.Error!p.Policy {
    if (bytes.len < 8 or bytes.len > (contracts.Limits{}).access_acl_bytes)
        return error.AccessReceiptInvalid;
    if (bytes[0] != 2 or bytes[1] != 0 or
        std.mem.readInt(u16, bytes[6..8], .little) != 0) return error.AccessConflict;
    if (std.mem.readInt(u16, bytes[2..4], .little) != bytes.len) return error.AccessReceiptInvalid;
    const count = std.mem.readInt(u16, bytes[4..6], .little);
    if (count != 1 and count != 2) return error.AccessConflict;
    var offset: usize = 8;
    const owner_mask = try ace(bytes, &offset, owner.bytes[0..owner.length]);
    const everyone_mask = if (count == 2) try ace(bytes, &offset, everyone_sid) else 0;
    if (offset != bytes.len) return error.AccessReceiptInvalid;
    const result: p.Policy = .{
        .kind = kind,
        .owner = try decodeMask(kind, owner_mask, true),
        .everyone = try decodeMask(kind, everyone_mask, false),
    };
    p.validate(result) catch return error.AccessConflict;
    return result;
}

fn ace(bytes: []const u8, offset: *usize, sid: []const u8) t.Error!u32 {
    if (offset.* > bytes.len or bytes.len - offset.* < 8) return error.AccessReceiptInvalid;
    const value = bytes[offset.*..];
    const length = std.mem.readInt(u16, value[2..4], .little);
    if (length < 8 or length > value.len) return error.AccessReceiptInvalid;
    if (value[0] != 0 or value[1] != 0) return error.AccessConflict;
    if (!std.mem.eql(u8, value[8..length], sid)) return error.AccessConflict;
    offset.* += length;
    return std.mem.readInt(u32, value[4..8], .little);
}

fn decodeMask(kind: p.Kind, value: u32, owner: bool) t.Error!p.Rights {
    for (0..8) |bits| {
        const rights = p.Rights.fromBits(std.math.cast(u3, bits) orelse
            return error.AccessReceiptInvalid);
        if (kind == .directory and rights.execute) continue;
        if (mask(kind, rights, owner) == value) return rights;
    }
    return error.AccessConflict;
}

fn validateSid(bytes: []const u8) t.Error!void {
    if (bytes.len < 8 or bytes.len > 68 or bytes[0] != 1) return error.AccessReceiptInvalid;
    if (bytes.len != 8 + @as(usize, bytes[1]) * 4) return error.AccessReceiptInvalid;
}
