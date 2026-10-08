//! Portable discretionary access intent. Native permission bits are never author input.
const std = @import("std");

pub const Kind = enum(u8) { file = 1, directory = 2 };
pub const Rights = struct {
    read: bool = false,
    write: bool = false,
    execute: bool = false,

    pub fn bits(value: Rights) u3 {
        return @as(u3, @intFromBool(value.read)) |
            (@as(u3, @intFromBool(value.write)) << 1) |
            (@as(u3, @intFromBool(value.execute)) << 2);
    }

    pub fn fromBits(value: u3) Rights {
        return .{ .read = value & 1 != 0, .write = value & 2 != 0, .execute = value & 4 != 0 };
    }
};
pub const Policy = struct { schema: u32 = 1, kind: Kind, owner: Rights, everyone: Rights };
pub const Error = error{AccessPolicyInvalid};

pub fn validate(value: Policy) Error!void {
    if (value.schema != 1 or !value.owner.read) return error.AccessPolicyInvalid;
    if (value.everyone.bits() & ~value.owner.bits() != 0) return error.AccessPolicyInvalid;
    for ([_]Rights{ value.owner, value.everyone }) |rights| {
        if (rights.write and !rights.read) return error.AccessPolicyInvalid;
        if (rights.execute and !rights.read) return error.AccessPolicyInvalid;
        if (value.kind == .directory and rights.execute) return error.AccessPolicyInvalid;
    }
}

pub fn private(kind: Kind) Policy {
    return .{ .kind = kind, .owner = .{ .read = true, .write = true }, .everyone = .{} };
}

pub fn equal(left: Policy, right: Policy) bool {
    return left.schema == right.schema and left.kind == right.kind and
        left.owner.bits() == right.owner.bits() and left.everyone.bits() == right.everyone.bits();
}

test "N2-ACCESS-01: positive grants have one cross-platform interpretation" {
    for (0..8) |owner| for (0..8) |everyone| {
        const o = std.math.cast(u3, owner) orelse return error.TestUnexpectedResult;
        const e = std.math.cast(u3, everyone) orelse return error.TestUnexpectedResult;
        const value: Policy = .{ .kind = .file, .owner = .fromBits(o), .everyone = .fromBits(e) };
        const valid = o & 1 != 0 and e & ~o == 0 and (o & 6 == 0 or o & 1 != 0) and
            (e & 6 == 0 or e & 1 != 0);
        if (valid) {
            try validate(value);
        } else {
            try std.testing.expectError(error.AccessPolicyInvalid, validate(value));
        }
    };
    try std.testing.expectError(error.AccessPolicyInvalid, validate(.{
        .kind = .directory,
        .owner = .{ .read = true, .execute = true },
        .everyone = .{},
    }));
}

test "N2-ACCESS-01: owner-none cannot bypass the recovery access floor" {
    for ([_]Kind{ .file, .directory }) |kind| {
        try std.testing.expectError(error.AccessPolicyInvalid, validate(.{
            .kind = kind,
            .owner = .{},
            .everyone = .{},
        }));
    }
}
