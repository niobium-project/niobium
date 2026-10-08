const std = @import("std");
const platform = @import("platform");
const policy = @import("access_policy");

pub const Error = platform.Error || policy.Error || error{
    AccessUnsupported,
    AccessConflict,
    AccessDrift,
    AccessOwnerMismatch,
    AccessReceiptInvalid,
    AccessLimit,
    AccessExists,
    AccessWrongKind,
};
pub const Os = enum(u8) { linux = 1, macos = 2, windows = 3 };
/// The native SID ABI has a maximum of 68 bytes; POSIX IDs occupy four bytes.
pub const Owner = struct {
    length: u8 = 0,
    bytes: [68]u8 align(4) = @splat(0),

    pub fn equal(a: Owner, b: Owner) bool {
        if (a.length > a.bytes.len or b.length > b.bytes.len) return false;
        return a.length == b.length and std.mem.eql(u8, a.bytes[0..a.length], b.bytes[0..b.length]);
    }
};
pub const Identity = struct { volume: u64, inode_low: u64, inode_high: u64 };
/// Native data has no relationship to file content hashes. Buffers belong to the caller's arena.
pub const Observation = struct {
    os: Os,
    identity: Identity,
    owner: Owner,
    policy: policy.Policy,
    native: []const u8,
};

pub fn status(value: i32) Error!void {
    return switch (value) {
        0 => {},
        2 => error.FsAccessDenied,
        3 => error.AccessUnsupported,
        4 => error.AccessLimit,
        5 => error.AccessExists,
        6 => error.FsNotFound,
        7 => error.FsNoSpace,
        8 => error.OutOfMemory,
        9 => error.AccessWrongKind,
        10 => error.FsSharingViolation,
        else => error.FsIo,
    };
}
