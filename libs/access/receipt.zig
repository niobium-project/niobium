//! Portable envelope around platform-specific permission receipts. No paths or handles are stored.
const std = @import("std");
const contracts = @import("contracts");
const t = @import("types.zig");
const p = @import("access_policy");
const header = 64;
const magic = "NBACCESS";

pub fn encode(arena: std.mem.Allocator, value: t.Observation) t.Error![]const u8 {
    try p.validate(value.policy);
    if (value.owner.length == 0 or value.owner.length > value.owner.bytes.len)
        return error.AccessReceiptInvalid;
    if (value.native.len > (contracts.Limits{}).access_acl_bytes) return error.AccessLimit;
    const bytes = try arena.alloc(u8, header + value.owner.length + value.native.len);
    @memset(bytes, 0);
    @memcpy(bytes[0..8], magic);
    std.mem.writeInt(u32, bytes[8..12], 1, .little);
    bytes[12] = @backingInt(value.os);
    bytes[13] = @backingInt(value.policy.kind);
    bytes[14] = value.policy.owner.bits();
    bytes[15] = value.policy.everyone.bits();
    bytes[16] = value.owner.length;
    std.mem.writeInt(u64, bytes[24..32], value.identity.volume, .little);
    std.mem.writeInt(u64, bytes[32..40], value.identity.inode_low, .little);
    std.mem.writeInt(u64, bytes[40..48], value.identity.inode_high, .little);
    const length = std.math.cast(u32, value.native.len) orelse return error.AccessLimit;
    std.mem.writeInt(u32, bytes[48..52], length, .little);
    @memcpy(bytes[header..][0..value.owner.length], value.owner.bytes[0..value.owner.length]);
    @memcpy(bytes[header + value.owner.length ..], value.native);
    return bytes;
}

pub fn decode(arena: std.mem.Allocator, bytes: []const u8) t.Error!t.Observation {
    if (bytes.len < header or bytes.len > header + 68 + (contracts.Limits{}).access_acl_bytes)
        return error.AccessReceiptInvalid;
    if (!std.mem.eql(u8, bytes[0..8], magic) or
        std.mem.readInt(u32, bytes[8..12], .little) != 1) return error.AccessReceiptInvalid;
    for (bytes[17..24]) |byte| if (byte != 0) return error.AccessReceiptInvalid;
    for (bytes[52..64]) |byte| if (byte != 0) return error.AccessReceiptInvalid;
    const os = std.enums.fromInt(t.Os, bytes[12]) orelse return error.AccessReceiptInvalid;
    const kind = std.enums.fromInt(p.Kind, bytes[13]) orelse return error.AccessReceiptInvalid;
    const owner_bits = std.math.cast(u3, bytes[14]) orelse return error.AccessReceiptInvalid;
    const everyone_bits = std.math.cast(u3, bytes[15]) orelse return error.AccessReceiptInvalid;
    const length = std.mem.readInt(u32, bytes[48..52], .little);
    var owner: t.Owner = .{ .length = bytes[16] };
    if (owner.length == 0 or owner.length > owner.bytes.len) return error.AccessReceiptInvalid;
    if (bytes.len != header + @as(usize, owner.length) + length) return error.AccessReceiptInvalid;
    @memcpy(owner.bytes[0..owner.length], bytes[header..][0..owner.length]);
    const policy: p.Policy = .{
        .kind = kind,
        .owner = .fromBits(owner_bits),
        .everyone = .fromBits(everyone_bits),
    };
    try p.validate(policy);
    return .{
        .os = os,
        .identity = .{
            .volume = std.mem.readInt(u64, bytes[24..32], .little),
            .inode_low = std.mem.readInt(u64, bytes[32..40], .little),
            .inode_high = std.mem.readInt(u64, bytes[40..48], .little),
        },
        .owner = owner,
        .policy = policy,
        .native = try arena.dupe(u8, bytes[header + owner.length ..]),
    };
}

pub fn same(a: t.Observation, b: t.Observation) bool {
    return a.os == b.os and std.meta.eql(a.identity, b.identity) and
        a.owner.equal(b.owner) and p.equal(a.policy, b.policy) and
        std.mem.eql(u8, a.native, b.native);
}
