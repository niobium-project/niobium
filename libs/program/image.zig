//! Bounded product image inside a reserved Mach-O section. Final signing may move EOF, so the
//! section table, not an executable trailer, locates the package.

const std = @import("std");
const contracts = @import("contracts");
const root = @import("root.zig");

pub const capacity: usize = (contracts.Limits{}).program_image_bytes;
pub const header_bytes: usize = 128;
pub const magic = "NIOPROG1";
pub const runtime_magic = "NIORT001";
pub const Error = root.Error || error{
    ImageInvalid,
    ImageMissing,
    ImageCapacity,
    ImageUnsupported,
};
pub const Section = struct { offset: usize, size: usize };

pub fn pack(arena: std.mem.Allocator, program_json: []const u8) Error![]const u8 {
    if (program_json.len > capacity - header_bytes) return error.ImageCapacity;
    const length = std.math.cast(u32, program_json.len) orelse return error.ImageCapacity;
    const bytes = try arena.alloc(u8, header_bytes + program_json.len);
    @memset(bytes, 0);
    @memcpy(bytes[0..8], magic);
    std.mem.writeInt(u32, bytes[8..12], 1, .little);
    std.mem.writeInt(u32, bytes[12..16], length, .little);
    std.crypto.hash.sha2.Sha256.hash(program_json, bytes[16..48], .{});
    @memcpy(bytes[header_bytes..], program_json);
    return bytes;
}

pub fn unpack(bytes: []const u8) Error![]const u8 {
    if (bytes.len < header_bytes or bytes.len > capacity) return error.ImageInvalid;
    if (!std.mem.eql(u8, bytes[0..8], magic)) return error.ImageMissing;
    if (try integer(u32, bytes, 8) != 1) return error.ImageUnsupported;
    const length = try integer(u32, bytes, 12);
    if (length > bytes.len - header_bytes) return error.ImageInvalid;
    for (bytes[80..header_bytes]) |byte| if (byte != 0) return error.ImageInvalid;
    const program_json = bytes[header_bytes..][0..length];
    var hash: [32]u8 = undefined; // SAFETY: hash fills the complete output.
    std.crypto.hash.sha2.Sha256.hash(program_json, &hash, .{});
    if (!std.mem.eql(u8, &hash, bytes[16..48])) return error.ProgramDigest;
    for (bytes[header_bytes + length ..]) |byte| if (byte != 0) return error.ImageInvalid;
    return program_json;
}

pub fn embed(
    arena: std.mem.Allocator,
    runtime_template: []const u8,
    program_json: []const u8,
) Error![]u8 {
    const section = try productSection(runtime_template);
    if (section.size != capacity) return error.ImageCapacity;
    try validateTemplate(runtime_template[section.offset..][0..section.size]);
    const package = try pack(arena, program_json);
    const output = try arena.dupe(u8, runtime_template);
    const slot = output[section.offset..][0..section.size];
    @memset(slot, 0);
    @memcpy(slot[0..package.len], package);
    std.crypto.hash.sha2.Sha256.hash(runtime_template, slot[48..80], .{});
    return output;
}

fn validateTemplate(slot: []const u8) Error!void {
    if (slot.len != capacity) return error.ImageCapacity;
    if (!std.mem.eql(u8, slot[0..8], runtime_magic)) return error.ImageUnsupported;
    if (try integer(u32, slot, 8) != 1) return error.ImageUnsupported;
    if (try integer(u32, slot, 12) != capacity) return error.ImageCapacity;
    for (slot[16..]) |byte| if (byte != 0) return error.ImageInvalid;
}

pub fn productFromExecutable(bytes: []const u8) Error![]const u8 {
    const section = try productSection(bytes);
    return unpack(bytes[section.offset..][0..section.size]);
}

pub fn productSection(bytes: []const u8) Error!Section {
    if (try integer(u32, bytes, 0) != 0xfeedfacf) return error.ImageUnsupported;
    if (try integer(u32, bytes, 4) != 0x0100000c) return error.ImageUnsupported;
    if (try integer(u32, bytes, 12) != 2) return error.ImageUnsupported;
    const commands = try integer(u32, bytes, 16);
    const command_bytes = try integer(u32, bytes, 20);
    if (commands > 128 or bytes.len < 32) return error.ImageInvalid;
    if (command_bytes > bytes.len - 32) return error.ImageInvalid;
    var offset: usize = 32;
    var found: ?Section = null;
    for (0..commands) |_| {
        const kind = try integer(u32, bytes, offset);
        const length = try integer(u32, bytes, offset + 4);
        if (length < 8 or length > 32 + command_bytes - offset) return error.ImageInvalid;
        if (kind == 0x19) {
            if (try segment(bytes, offset, length)) |section| {
                if (found != null) return error.ImageInvalid;
                found = section;
            }
        }
        offset += length;
    }
    if (offset != 32 + command_bytes) return error.ImageInvalid;
    return found orelse error.ImageMissing;
}

fn segment(bytes: []const u8, offset: usize, length: u32) Error!?Section {
    if (length < 72) return error.ImageInvalid;
    const sections = try integer(u32, bytes, offset + 64);
    if (sections > 256 or sections > (length - 72) / 80) return error.ImageInvalid;
    var found: ?Section = null;
    for (0..sections) |index| {
        const position = offset + 72 + index * 80;
        if (!name(bytes[position..][0..16], "__nbproduct")) continue;
        if (!name(bytes[position + 16 ..][0..16], "__DATA")) return error.ImageInvalid;
        if (found != null) return error.ImageInvalid;
        const size_u64 = try integer(u64, bytes, position + 40);
        const size = std.math.cast(usize, size_u64) orelse return error.ImageCapacity;
        const start = try integer(u32, bytes, position + 48);
        if (size != capacity or start > bytes.len) return error.ImageCapacity;
        if (size > bytes.len - start) return error.ImageInvalid;
        found = .{ .offset = start, .size = size };
    }
    return found;
}

fn name(bytes: []const u8, expected: []const u8) bool {
    std.debug.assert(bytes.len == 16);
    const end = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
    return std.mem.eql(u8, bytes[0..end], expected);
}

fn integer(comptime T: type, bytes: []const u8, offset: usize) Error!T {
    if (offset > bytes.len or @sizeOf(T) > bytes.len - offset) return error.ImageInvalid;
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}

test "N2-IMAGE-01: image authenticates contents and rejects capacity overflow" {
    const arena = std.testing.allocator;
    const package = try pack(arena, "{\"schema\":1}");
    defer arena.free(package);
    try std.testing.expectEqualStrings("{\"schema\":1}", try unpack(package));
    const corrupt = try arena.dupe(u8, package);
    defer arena.free(corrupt);
    corrupt[header_bytes] ^= 1;
    try std.testing.expectError(error.ProgramDigest, unpack(corrupt));
    try std.testing.expectError(error.ImageInvalid, unpack(package[0..12]));
    const oversized = try arena.alloc(u8, capacity);
    defer arena.free(oversized);
    try std.testing.expectError(error.ImageCapacity, pack(arena, oversized));
}

test "N2-IMAGE-01: template must be an arm64 executable" {
    var bytes: [32]u8 = @splat(0);
    std.mem.writeInt(u32, bytes[0..4], 0xfeedfacf, .little);
    std.mem.writeInt(u32, bytes[4..8], 0x01000007, .little);
    std.mem.writeInt(u32, bytes[12..16], 2, .little);
    try std.testing.expectError(error.ImageUnsupported, productSection(&bytes));
    std.mem.writeInt(u32, bytes[4..8], 0x0100000c, .little);
    std.mem.writeInt(u32, bytes[12..16], 1, .little);
    try std.testing.expectError(error.ImageUnsupported, productSection(&bytes));
}

test "N2-IMAGE-01: template declares supported ABI and empty reserved capacity" {
    const bytes = try std.testing.allocator.alloc(u8, capacity);
    defer std.testing.allocator.free(bytes);
    @memset(bytes, 0);
    @memcpy(bytes[0..8], runtime_magic);
    std.mem.writeInt(u32, bytes[8..12], 1, .little);
    std.mem.writeInt(u32, bytes[12..16], capacity, .little);
    try validateTemplate(bytes);
    std.mem.writeInt(u32, bytes[8..12], 2, .little);
    try std.testing.expectError(error.ImageUnsupported, validateTemplate(bytes));
    @memcpy(bytes[0..8], magic);
    try std.testing.expectError(error.ImageUnsupported, validateTemplate(bytes));
}
