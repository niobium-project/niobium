//! Standard-format ad-hoc measurement vectors, independent of publisher identity checks.

const std = @import("std");
const image = @import("root.zig");
const signature = @import("signature.zig");
const io = std.testing.io;

fn fixture() [768]u8 {
    var bytes: [768]u8 = @splat(0);
    @memset(bytes[0..512], 0x61);
    put(&bytes, 512, 0xfade0cc0);
    put(&bytes, 516, 200);
    put(&bytes, 520, 2);
    put(&bytes, 524, 0);
    put(&bytes, 528, 28);
    put(&bytes, 532, 2);
    put(&bytes, 536, 188);
    const code = 512 + 28;
    put(&bytes, code, 0xfade0c02);
    put(&bytes, code + 4, 160);
    put(&bytes, code + 8, 0x20100);
    put(&bytes, code + 12, 2);
    put(&bytes, code + 16, 128);
    put(&bytes, code + 20, 48);
    put(&bytes, code + 24, 2);
    put(&bytes, code + 28, 1);
    put(&bytes, code + 32, 512);
    bytes[code + 36] = 32;
    bytes[code + 37] = 2;
    bytes[code + 39] = 12;
    @memcpy(bytes[code + 48 ..][0..5], "test\x00");
    put(&bytes, 700, 0xfade0c01);
    put(&bytes, 704, 12);
    std.crypto.hash.sha2.Sha256.hash(bytes[700..712], bytes[code + 64 ..][0..32], .{});
    std.crypto.hash.sha2.Sha256.hash(bytes[0..512], bytes[code + 128 ..][0..32], .{});
    return bytes;
}

fn put(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn verify(bytes: []const u8) image.Error!void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try signature.verifyRange(arena.allocator(), io, .{ .bytes = bytes }, .{
        .offset = 512,
        .length = bytes.len - 512,
    }, .{});
}

test "N2-SIGNATURE-01 code pages payload and special-slot hashes are all verified" {
    var bytes = fixture();
    try verify(&bytes);
    bytes[1] ^= 1;
    try std.testing.expectError(error.SignatureDigest, verify(&bytes));
    bytes = fixture();
    bytes[512 + 28 + 128] ^= 1;
    try std.testing.expectError(error.SignatureDigest, verify(&bytes));
    bytes = fixture();
    bytes[708] ^= 1;
    try std.testing.expectError(error.SignatureDigest, verify(&bytes));
}

test "N2-SIGNATURE-01 malformed slot ranges coverage algorithms and padding are rejected" {
    const cases = [_]struct { offset: usize, value: u32, expected: image.Error }{
        .{ .offset = 528, .value = 0, .expected = error.SignatureInvalid },
        .{ .offset = 536, .value = 28, .expected = error.SignatureInvalid },
        .{ .offset = 540 + 28, .value = 2, .expected = error.SignatureInvalid },
        .{ .offset = 540 + 32, .value = 511, .expected = error.SignatureInvalid },
        .{ .offset = 540 + 16, .value = 20, .expected = error.SignatureInvalid },
        .{ .offset = 540 + 8, .value = 0x30000, .expected = error.SignatureUnsupported },
        .{ .offset = 540 + 12, .value = 0, .expected = error.SignatureUnsupported },
    };
    for (cases) |case| {
        var bytes = fixture();
        put(&bytes, case.offset, case.value);
        try std.testing.expectError(case.expected, verify(&bytes));
    }
    var bytes = fixture();
    bytes[767] = 1;
    try std.testing.expectError(error.SignatureInvalid, verify(&bytes));
    bytes = fixture();
    bytes[540 + 37] = 1;
    try std.testing.expectError(error.SignatureUnsupported, verify(&bytes));
}

fn allocate(gpa: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const bytes = fixture();
    try signature.verifyRange(arena.allocator(), io, .{ .bytes = &bytes }, .{
        .offset = 512,
        .length = 256,
    }, .{});
}

test "N2-SIGNATURE-01 verifier allocation failures are bounded" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocate, .{});
}
