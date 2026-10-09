//! Test fixture builder: ustar archives and zstd frames made of raw / RLE blocks, so malicious
//! archives are constructed byte-exactly without libzstd (which only the packager links).

const std = @import("std");

pub const Tar = @import("tar").fixture.Tar;

fn small(n: u64) error{Overflow}!u21 {
    return std.math.cast(u21, n) orelse error.Overflow;
}

const zstd_magic = 0xFD2FB528;
const block_max = 1 << 17;

fn frameHeader(out: *std.ArrayList(u8), gpa: std.mem.Allocator) !void {
    var magic: [4]u8 = undefined; // SAFETY: written by writeInt.
    std.mem.writeInt(u32, &magic, zstd_magic, .little);
    try out.appendSlice(gpa, &magic);
    // Descriptor: no content size, not single segment, no checksum; window 2^(10+10) = 1 MiB.
    try out.appendSlice(gpa, &.{ 0x00, 10 << 3 });
}

fn blockHeader(
    out: *std.ArrayList(u8),
    gpa: std.mem.Allocator,
    last: bool,
    kind: u2,
    size: u21,
) !void {
    const value: u24 = @as(u24, size) << 3 | @as(u24, kind) << 1 | @intFromBool(last);
    var bytes: [3]u8 = undefined; // SAFETY: written by writeInt.
    std.mem.writeInt(u24, &bytes, value, .little);
    try out.appendSlice(gpa, &bytes);
}

/// One zstd frame of raw blocks holding `payload`.
pub fn zstdRaw(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try frameHeader(&out, gpa);
    var rest = payload;
    // loop-bound: each iteration consumes up to block_max bytes of a finite payload.
    while (true) {
        const n = @min(rest.len, block_max);
        try blockHeader(&out, gpa, n == rest.len, 0, try small(n));
        try out.appendSlice(gpa, rest[0..n]);
        rest = rest[n..];
        if (rest.len == 0) break;
    }
    return out.toOwnedSlice(gpa);
}

/// `prefix` as raw blocks followed by `count` zero bytes as RLE blocks: a decompression bomb.
pub fn zstdBomb(gpa: std.mem.Allocator, prefix: []const u8, count: u64) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try frameHeader(&out, gpa);
    try blockHeader(&out, gpa, false, 0, try small(prefix.len));
    try out.appendSlice(gpa, prefix);
    var rest = count;
    while (rest > 0) {
        const n = @min(rest, block_max);
        rest -= n;
        try blockHeader(&out, gpa, rest == 0, 1, try small(n));
        try out.append(gpa, 0);
    }
    return out.toOwnedSlice(gpa);
}
