//! Compiled product model shared by the compiler and runtime. Author programs construct typed
//! values; this module owns normalization and strict machine-protocol decoding.

const std = @import("std");
const contracts = @import("contracts");

pub const validation = @import("validate.zig");
pub const profile = @import("profile.zig");
pub const value = @import("value.zig");
pub const model = @import("model.zig");
pub const wit = @import("wit.zig");
pub const worker = @import("worker.zig");
pub const Error = contracts.json.DecodeError || error{
    ProgramInvalid,
    ProgramLimit,
    ProgramDuplicate,
    ProgramReference,
    ProgramDigest,
    ProgramPath,
    ProgramUnsupported,
};

pub const Migration = struct { id: []const u8, from: u32, to: u32 };

pub fn digest(arena: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    var hash: [32]u8 = undefined; // SAFETY: hash writes every byte.
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    return encodeHex(arena, &hash);
}

pub fn encodeHex(arena: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    if (bytes.len > (contracts.Limits{}).program_blob_bytes) return error.ProgramLimit;
    const output = try arena.alloc(u8, bytes.len * 2);
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |byte, i| {
        output[2 * i] = alphabet[byte >> 4];
        output[2 * i + 1] = alphabet[byte & 15];
    }
    return output;
}

pub fn decodeHex(arena: std.mem.Allocator, text: []const u8) Error![]u8 {
    if (text.len > (contracts.Limits{}).program_blob_bytes * 2) return error.ProgramLimit;
    if (text.len % 2 != 0) return error.ProgramInvalid;
    const output = try arena.alloc(u8, text.len / 2);
    for (output, 0..) |*byte, i| {
        byte.* = (try nibble(text[2 * i])) * 16 + try nibble(text[2 * i + 1]);
    }
    return output;
}

pub fn nibble(byte: u8) Error!u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        else => error.ProgramInvalid,
    };
}

pub fn find(comptime T: type, items: []const T, id: []const u8) ?T {
    for (items) |item| {
        if (std.mem.eql(u8, item.id, id)) return item;
    }
    return null;
}

test {
    _ = model;
    _ = profile;
    _ = value;
    _ = validation;
    _ = @import("program_test.zig");
}
