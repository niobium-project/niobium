//! Portable SHA-256 ad-hoc measurement verification, not publisher/CMS or Gatekeeper trust.
//! Native format constants follow Apple's published CS_SuperBlob and CS_CodeDirectory layouts.

const std = @import("std");
const contracts = @import("contracts");
const image = @import("root.zig");
const stream = @import("stream.zig");

const Blob = struct { slot: u32, range: image.Range, magic: u32 };

pub fn verify(
    arena: std.mem.Allocator,
    io: std.Io,
    source: image.Source,
    limits: contracts.Limits,
) image.Error!void {
    const layout = try image.native.inspect(arena, io, source, limits);
    if (layout.format != .macho) return error.SignatureUnsupported;
    try verifyRange(arena, io, source, layout.signature, limits);
}

pub fn verifyRange(
    arena: std.mem.Allocator,
    io: std.Io,
    source: image.Source,
    signature: image.Range,
    limits: contracts.Limits,
) image.Error!void {
    if (source.size() > limits.native_image_bytes or signature.length < 12 or
        signature.length > limits.native_signature_bytes or
        try signature.end() != source.size()) return error.SignatureInvalid;
    if (try number(u32, io, source, signature.offset) != 0xfade0cc0) return error.SignatureInvalid;
    const size = try number(u32, io, source, signature.offset + 4);
    const count = try number(u32, io, source, signature.offset + 8);
    if (count == 0 or count > limits.native_sections or size > signature.length or
        @as(u64, count) * 8 + 12 > size) return error.SignatureInvalid;
    const blobs = try arena.alloc(Blob, count);
    var primary = false;
    for (blobs, 0..) |*blob, index| {
        const entry = signature.offset + 12 + index * 8;
        const slot = try number(u32, io, source, entry);
        const offset = try number(u32, io, source, entry + 4);
        if (offset < 12 + count * 8 or offset > size or size - offset < 8) {
            return error.SignatureInvalid;
        }
        const start = signature.offset + offset;
        const length = try number(u32, io, source, start + 4);
        if (length < 8 or length > size - offset) return error.SignatureInvalid;
        blob.* = .{
            .slot = slot,
            .range = .{ .offset = start, .length = length },
            .magic = try number(u32, io, source, start),
        };
        for (blobs[0..index]) |prior| {
            if (prior.slot == slot or (prior.range.offset < try blob.range.end() and
                start < try prior.range.end())) return error.SignatureInvalid;
        }
        if (slot == 0) primary = true;
    }
    if (!primary) return error.SignatureInvalid;
    for (blobs) |blob| {
        if (blob.slot == 0 or (blob.slot >= 0x1000 and blob.slot < 0x1005)) {
            try directory(io, source, signature.offset, blob, blobs, limits);
        } else if (blob.slot == 0x10000) {
            if (blob.magic != 0xfade0b01 or blob.range.length != 8)
                return error.SignatureUnsupported;
        } else if (!specialMagic(blob)) return error.SignatureUnsupported;
    }
    try zero(io, source, signature.offset + size, try signature.end());
}

fn directory(
    io: std.Io,
    source: image.Source,
    coverage: u64,
    blob: Blob,
    blobs: []const Blob,
    limits: contracts.Limits,
) image.Error!void {
    if (blob.magic != 0xfade0c02 or blob.range.length < 48) return error.SignatureInvalid;
    const at = blob.range.offset;
    const version = try number(u32, io, source, at + 8);
    const minimum: u32 = switch (version) {
        0x20100 => 48,
        0x20200 => 52,
        0x20300 => 64,
        0x20400 => 88,
        0x20500 => 96,
        else => return error.SignatureUnsupported,
    };
    if (blob.range.length < minimum) return error.SignatureInvalid;
    const flags = try number(u32, io, source, at + 12);
    if (flags & 2 == 0 or flags & ~@as(u32, 0x33f02) != 0) return error.SignatureUnsupported;
    const hashes = try number(u32, io, source, at + 16);
    const identifier = try number(u32, io, source, at + 20);
    const special = try number(u32, io, source, at + 24);
    const pages = try number(u32, io, source, at + 28);
    var code_limit: u64 = try number(u32, io, source, at + 32);
    if (version >= 0x20300) {
        const extended = try number(u64, io, source, at + 56);
        if (extended > 0) code_limit = extended;
        if (try number(u32, io, source, at + 52) != 0) return error.SignatureInvalid;
    }
    var algorithm: [4]u8 = undefined; // SAFETY: source fills the algorithm descriptor.
    try source.read(io, at + 36, &algorithm);
    if (algorithm[0] != 32 or algorithm[1] != 2 or algorithm[2] != 0 or
        (algorithm[3] != 12 and algorithm[3] != 14 and algorithm[3] != 16))
    {
        return error.SignatureUnsupported;
    }
    const page: u64 = @as(u64, 1) << (std.math.cast(u6, algorithm[3]) orelse
        return error.SignatureInvalid);
    if (code_limit != coverage or pages != (code_limit + page - 1) / page or
        special > limits.native_sections) return error.SignatureInvalid;
    if (@as(u64, special) * 32 > hashes or hashes > blob.range.length or
        @as(u64, pages) * 32 > blob.range.length - hashes) return error.SignatureInvalid;
    const metadata_end = hashes - special * 32;
    if (metadata_end < minimum or identifier < minimum or identifier >= metadata_end) {
        return error.SignatureInvalid;
    }
    try string(io, source, at + identifier, at + metadata_end, limits.path_bytes);
    if (try number(u32, io, source, at + 40) != 0 or
        try number(u32, io, source, at + 44) != 0) return error.SignatureUnsupported;
    if (version >= 0x20200 and try number(u32, io, source, at + 48) != 0) {
        return error.SignatureUnsupported;
    }
    if (version >= 0x20500 and try number(u32, io, source, at + 92) != 0) {
        return error.SignatureUnsupported;
    }
    if (version >= 0x20400) {
        const base = try number(u64, io, source, at + 64);
        const length = try number(u64, io, source, at + 72);
        const exec_flags = try number(u64, io, source, at + 80);
        if (base > code_limit or length > code_limit - base or exec_flags & ~@as(u64, 1) != 0) {
            return error.SignatureUnsupported;
        }
    }
    try pagesAndSpecial(io, source, at + hashes, code_limit, page, pages, special, blobs);
}

fn pagesAndSpecial(
    io: std.Io,
    source: image.Source,
    hashes: u64,
    limit: u64,
    page: u64,
    pages: u32,
    special: u32,
    blobs: []const Blob,
) image.Error!void {
    for (0..pages) |index| {
        const offset = index * page;
        const digest = try stream.hash(io, .{
            .source = source,
            .offset = offset,
            .length = @min(page, limit - offset),
        });
        try equalHash(io, source, hashes + index * 32, digest);
    }
    for (1..@as(usize, special) + 1) |index| {
        const entry = for (blobs) |blob| {
            if (blob.slot == index) break blob;
        } else null;
        const digest = if (entry) |blob| try stream.hash(io, .{
            .source = source,
            .offset = blob.range.offset,
            .length = blob.range.length,
        }) else @as([32]u8, @splat(0));
        try equalHash(io, source, hashes - index * 32, digest);
    }
    for (blobs) |blob| {
        if (blob.slot > 0 and blob.slot < 0x1000 and blob.slot > special) {
            return error.SignatureInvalid;
        }
    }
}

fn equalHash(io: std.Io, source: image.Source, offset: u64, expected: [32]u8) image.Error!void {
    var bytes: [32]u8 = undefined; // SAFETY: source initializes the stored hash.
    try source.read(io, offset, &bytes);
    if (!std.mem.eql(u8, &bytes, &expected)) return error.SignatureDigest;
}

fn specialMagic(blob: Blob) bool {
    return switch (blob.slot) {
        2 => blob.magic == 0xfade0c01,
        5 => blob.magic == 0xfade7171,
        7 => blob.magic == 0xfade7172,
        8, 9, 10, 11 => blob.magic == 0xfade8181,
        else => false,
    };
}

fn number(comptime T: type, io: std.Io, source: image.Source, offset: u64) image.Error!T {
    var bytes: [@sizeOf(T)]u8 = undefined; // SAFETY: read fills the integer representation.
    try source.read(io, offset, &bytes);
    return std.mem.readInt(T, &bytes, .big);
}

fn string(io: std.Io, source: image.Source, start: u64, end: u64, maximum: u16) image.Error!void {
    if (end <= start) return error.SignatureInvalid;
    for (0..@min(maximum, end - start)) |index| {
        if (try number(u8, io, source, start + index) == 0) return;
    }
    return error.SignatureInvalid;
}

fn zero(io: std.Io, source: image.Source, start: u64, end: u64) image.Error!void {
    var offset = start;
    var bytes: [4096]u8 = undefined; // SAFETY: read initializes the checked padding.
    while (offset < end) {
        const count = std.math.cast(usize, @min(bytes.len, end - offset)) orelse
            return error.SignatureInvalid;
        try source.read(io, offset, bytes[0..count]);
        for (bytes[0..count]) |byte| if (byte != 0) return error.SignatureInvalid;
        offset += count;
    }
}

test {
    _ = @import("signature_test.zig");
}
