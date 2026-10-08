//! Native mode and ACL normalization for newly created objects; existing ACLs are never merged.
const std = @import("std");
const builtin = @import("builtin");
const contracts = @import("contracts");
const b = @import("bindings.zig");
const p = @import("access_policy");
const t = @import("types.zig");
const os: t.Os = if (builtin.os.tag == .macos) .macos else .linux;
const immutable_flags: u32 = if (os == .macos) 0x00060006 else 0x30;

pub fn stat(handle: usize) t.Error!b.Stat {
    var result: b.Stat = undefined; // SAFETY: the bridge initializes every field on success.
    try t.status(b.nb_access_stat_handle(handle, &result));
    try volume(result);
    if (result.kind != 1 and result.kind != 2) return error.AccessWrongKind;
    if (result.kind == 1 and result.nlink != 1) return error.AccessConflict;
    if (result.object_flags & immutable_flags != 0) return error.AccessUnsupported;
    return result;
}

fn volume(value: b.Stat) t.Error!void {
    if (value.volume_flags & (1 | 2 | 8) != 0) return error.AccessUnsupported;
    if (os == .macos) {
        const name = std.mem.sliceTo(&value.filesystem_name, 0);
        if (!std.mem.eql(u8, name, "apfs") and !std.mem.eql(u8, name, "hfs"))
            return error.AccessUnsupported;
    } else switch (value.filesystem) {
        0xef53, 0x58465342, 0x9123683e, 0x01021994 => {},
        else => return error.AccessUnsupported,
    }
}

pub fn parentSafe(handle: usize) t.Error!void {
    const value = try stat(handle);
    if (value.kind != 2) return error.AccessWrongKind;
    if (os == .macos) {
        var entries: u32 = 0;
        var flags: u32 = 0;
        try t.status(b.nb_access_posix_acl(
            handle,
            2,
            (contracts.Limits{}).access_acl_entries,
            &entries,
            &flags,
        ));
        if (entries > (contracts.Limits{}).access_acl_entries) return error.AccessLimit;
        // openat cannot supply an ACL atomically on Darwin. Refuse inherited authority.
        if (flags & ~@as(u32, 1) != 0) return error.AccessUnsupported;
    }
}

pub fn prepareNew(handle: usize, kind: p.Kind) t.Error!void {
    const value = try stat(handle);
    if (value.kind != @backingInt(kind)) return error.AccessWrongKind;
    try t.status(b.nb_access_posix_clear_acl(handle, value.kind, if (os == .macos) 1 else 0));
    try t.status(b.nb_access_posix_mode(handle, mode(p.private(kind))));
}

pub fn inspect(arena: std.mem.Allocator, handle: usize) t.Error!t.Observation {
    const value = try stat(handle);
    var entries: u32 = 0;
    var flags: u32 = 0;
    try t.status(b.nb_access_posix_acl(
        handle,
        value.kind,
        (contracts.Limits{}).access_acl_entries,
        &entries,
        &flags,
    ));
    if (entries != 0 or flags & ~@as(u32, 1) != 0) return error.AccessConflict;
    if (os == .linux and flags != 0) return error.AccessConflict;
    const kind: p.Kind = if (value.kind == 1) .file else .directory;
    const access = try fromMode(kind, value.mode & 0o7777);
    try checkExecution(access, value.volume_flags);
    var owner: t.Owner = .{ .length = 4 };
    std.mem.writeInt(u32, owner.bytes[0..4], value.uid, .little);
    const native = try arena.alloc(u8, 20);
    std.mem.writeInt(u32, native[0..4], value.mode & 0o7777, .little);
    std.mem.writeInt(u32, native[4..8], value.gid, .little);
    std.mem.writeInt(u32, native[8..12], value.object_flags, .little);
    std.mem.writeInt(u32, native[12..16], flags, .little);
    std.mem.writeInt(u32, native[16..20], value.volume_flags, .little);
    return .{
        .os = os,
        .identity = .{
            .volume = value.volume,
            .inode_low = value.inode_low,
            .inode_high = value.inode_high,
        },
        .owner = owner,
        .policy = access,
        .native = native,
    };
}

pub fn validateObservation(value: t.Observation) t.Error!void {
    if (value.os != os or value.owner.length != 4 or value.native.len != 20)
        return error.AccessReceiptInvalid;
    const bits = std.mem.readInt(u32, value.native[0..4], .little);
    const decoded = try fromMode(value.policy.kind, bits);
    if (!p.equal(decoded, value.policy)) return error.AccessReceiptInvalid;
    const flags = std.mem.readInt(u32, value.native[12..16], .little);
    if (flags > 1 or (os == .linux and flags != 0)) return error.AccessReceiptInvalid;
    if (std.mem.readInt(u32, value.native[8..12], .little) & immutable_flags != 0)
        return error.AccessReceiptInvalid;
    const mount = std.mem.readInt(u32, value.native[16..20], .little);
    if (mount & ~@as(u32, 4) != 0) return error.AccessReceiptInvalid;
    try checkExecution(value.policy, mount);
}

pub fn apply(handle: usize, current: t.Observation, target: p.Policy) t.Error!void {
    try checkExecution(target, std.mem.readInt(u32, current.native[16..20], .little));
    try t.status(b.nb_access_posix_clear_acl(
        handle,
        @backingInt(target.kind),
        if (os == .macos) 1 else 0,
    ));
    try t.status(b.nb_access_posix_mode(handle, mode(target)));
}

pub fn restore(handle: usize, current: t.Observation, prior: t.Observation) t.Error!void {
    if (!std.mem.eql(u8, current.native[4..12], prior.native[4..12]) or
        !std.mem.eql(u8, current.native[16..20], prior.native[16..20]))
        return error.AccessDrift;
    const flags = std.mem.readInt(u32, prior.native[12..16], .little);
    try t.status(b.nb_access_posix_clear_acl(handle, @backingInt(prior.policy.kind), flags));
    try t.status(b.nb_access_posix_mode(handle, mode(prior.policy)));
}

pub fn mode(value: p.Policy) u32 {
    const owner = unixBits(value.owner);
    const everyone = unixBits(value.everyone);
    return (owner << 6) | (everyone << 3) | everyone |
        (if (value.kind == .directory) @as(u32, 0o111) else 0);
}

fn unixBits(value: p.Rights) u32 {
    return (@as(u32, @intFromBool(value.read)) << 2) |
        (@as(u32, @intFromBool(value.write)) << 1) | @intFromBool(value.execute);
}

fn fromMode(kind: p.Kind, bits: u32) t.Error!p.Policy {
    if (bits > 0o777 or (bits >> 3) & 7 != bits & 7) return error.AccessConflict;
    if (kind == .directory and bits & 0o111 != 0o111) return error.AccessConflict;
    const value: p.Policy = .{
        .kind = kind,
        .owner = rights(kind, bits >> 6),
        .everyone = rights(kind, bits),
    };
    p.validate(value) catch return error.AccessConflict;
    return value;
}

fn rights(kind: p.Kind, bits: u32) p.Rights {
    return .{
        .read = bits & 4 != 0,
        .write = bits & 2 != 0,
        .execute = kind == .file and bits & 1 != 0,
    };
}

fn checkExecution(value: p.Policy, mount: u32) t.Error!void {
    if (value.kind == .file and value.owner.execute and mount & 4 != 0)
        return error.AccessUnsupported;
}
