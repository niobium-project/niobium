//! Checked positional reads and writes shared by native image formats.

const std = @import("std");
const image = @import("root.zig");

pub fn alignOffset(value: u64, alignment: u64) image.Error!u64 {
    std.debug.assert(alignment > 0);
    const padding = (alignment - value % alignment) % alignment;
    return std.math.add(u64, value, padding) catch error.ImageLimit;
}

pub fn hash(io: std.Io, body: image.Body) image.Error![32]u8 {
    return transfer(io, body, null, 0);
}

pub fn copy(io: std.Io, body: image.Body, output: std.Io.File, offset: u64) image.Error![32]u8 {
    return transfer(io, body, output, offset);
}

/// Move a terminal signature forward without rereading the original template or corrupting overlap.
pub fn move(io: std.Io, file: std.Io.File, range: image.Range, destination: u64) image.Error!void {
    std.debug.assert(destination >= range.offset);
    const source: image.Source = .{ .file = .{
        .handle = file,
        .length = (file.stat(io) catch return error.ImageWriteFailed).size,
    } };
    if (try range.end() > source.size()) return error.ImageInvalid;
    var buffer: [64 << 10]u8 = undefined; // SAFETY: read initializes each moved chunk.
    var remaining = range.length;
    while (remaining > 0) {
        const length = std.math.cast(usize, @min(buffer.len, remaining)) orelse
            return error.ImageLimit;
        remaining -= length;
        try source.read(io, range.offset + remaining, buffer[0..length]);
        const offset = std.math.add(u64, destination, remaining) catch return error.ImageLimit;
        file.writePositionalAll(io, buffer[0..length], offset) catch return error.ImageWriteFailed;
    }
}

fn transfer(io: std.Io, body: image.Body, output: ?std.Io.File, target: u64) image.Error![32]u8 {
    std.debug.assert(@sizeOf(u64) == 8);
    if (body.offset > body.source.size() or body.length > body.source.size() - body.offset) {
        return error.ImageInvalid;
    }
    var buffer: [64 << 10]u8 = undefined; // SAFETY: read fills each consumed slice.
    var hasher: std.crypto.hash.sha2.Sha256 = .init(.{});
    var offset: u64 = 0;
    while (offset < body.length) {
        const length = std.math.cast(usize, @min(body.length - offset, buffer.len)) orelse
            return error.ImageLimit;
        try body.source.read(io, body.offset + offset, buffer[0..length]);
        if (output) |file| {
            const position = std.math.add(u64, target, offset) catch return error.ImageLimit;
            file.writePositionalAll(io, buffer[0..length], position) catch
                return error.ImageWriteFailed;
        }
        hasher.update(buffer[0..length]);
        offset += length;
    }
    return hasher.finalResult();
}

pub fn checkZero(io: std.Io, source: image.Source, start: u64, end: u64) image.Error!void {
    if (end < start or end - start > 16) return error.ImageInvalid;
    var bytes: [16]u8 = undefined; // SAFETY: read fills the checked padding.
    const length = std.math.cast(usize, end - start) orelse return error.ImageLimit;
    try source.read(io, start, bytes[0..length]);
    for (bytes[0..length]) |byte| if (byte != 0) return error.ImageInvalid;
}

pub fn zero(io: std.Io, output: std.Io.File, start: u64, end: u64) image.Error!void {
    if (end < start or end - start > 16) return error.ImageInvalid;
    const bytes: [16]u8 = @splat(0);
    const length = std.math.cast(usize, end - start) orelse return error.ImageLimit;
    output.writePositionalAll(io, bytes[0..length], start) catch return error.ImageWriteFailed;
}

pub fn integer(comptime T: type, io: std.Io, source: image.Source, offset: u64) image.Error!T {
    var bytes: [@sizeOf(T)]u8 = undefined; // SAFETY: read fills every integer byte.
    try source.read(io, offset, &bytes);
    return std.mem.readInt(T, &bytes, .little);
}

pub fn set(
    comptime T: type,
    io: std.Io,
    output: std.Io.File,
    offset: u64,
    value: T,
) image.Error!void {
    var bytes: [@sizeOf(T)]u8 = undefined; // SAFETY: writeInt initializes every byte.
    std.mem.writeInt(T, &bytes, value, .little);
    output.writePositionalAll(io, &bytes, offset) catch return error.ImageWriteFailed;
}
