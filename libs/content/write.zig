//! Canonical uncompressed tar identity. Transport codecs and provenance are separate.

const std = @import("std");
const contracts = @import("contracts");
const tar = @import("tar");
const content = @import("root.zig");
const normalize = @import("transform.zig").normalize;

pub fn write(
    arena: std.mem.Allocator,
    io: std.Io,
    tree: content.Tree,
    output: *std.Io.Writer,
    limits: contracts.Limits,
) content.Error!content.ContainerRef {
    std.debug.assert(limits.path_bytes > 0);
    const normalized = try normalize(arena, tree.entries, limits);
    var stream: Stream = .{ .output = output, .limit = limits.expanded_bytes };
    for (normalized.entries) |entry| try stream.writeEntry(arena, io, entry);
    try stream.zeros(2 * tar.block_len);
    return .{ .sha256 = stream.hash.finalResult(), .bytes = stream.length };
}

const Stream = struct {
    output: *std.Io.Writer,
    limit: u64,
    hash: std.crypto.hash.sha2.Sha256 = .init(.{}),
    length: u64 = 0,

    fn push(self: *Stream, bytes: []const u8) content.Error!void {
        std.debug.assert(self.length <= self.limit);
        if (bytes.len > self.limit - self.length) return error.ContentLimit;
        self.output.writeAll(bytes) catch return error.ContentWriteFailed;
        self.hash.update(bytes);
        self.length += bytes.len;
    }

    fn zeros(self: *Stream, length: u64) content.Error!void {
        std.debug.assert(length <= 2 * tar.block_len);
        const bytes: [2 * tar.block_len]u8 = @splat(0);
        const count = std.math.cast(usize, length) orelse return error.ContentLimit;
        try self.push(bytes[0..count]);
    }

    fn writeEntry(
        self: *Stream,
        arena: std.mem.Allocator,
        io: std.Io,
        entry: content.Entry,
    ) content.Error!void {
        std.debug.assert(entry.path.len > 0);
        var pax: std.ArrayList(u8) = .empty;
        try pax.appendSlice(arena, try record(arena, "path", entry.path));
        if (entry.kind == .file) {
            const size = try arena.print("{d}", .{entry.body.length});
            try pax.appendSlice(arena, try record(arena, "size", size));
        } else if (entry.kind == .symlink) {
            try pax.appendSlice(arena, try record(arena, "linkpath", entry.link_target));
        }
        try self.header('x', "PaxHeader", 0o644, pax.items.len);
        try self.push(pax.items);
        try self.zeros(tar.padding(pax.items.len));
        const flag: u8 = switch (entry.kind) {
            .file => '0',
            .directory => '5',
            .symlink => '2',
        };
        const size = if (entry.body.length <= 0o77777777777) entry.body.length else 0;
        try self.header(flag, "entry", entry.mode, size);
        if (entry.kind == .file) try self.writeBody(io, entry.body);
    }

    fn header(self: *Stream, flag: u8, name: []const u8, mode: u16, size: u64) content.Error!void {
        std.debug.assert(name.len <= 100);
        var block: [tar.block_len]u8 = @splat(0);
        @memcpy(block[0..name.len], name);
        try octal(block[100..108], mode);
        try octal(block[108..116], 0);
        try octal(block[116..124], 0);
        try octal(block[124..136], size);
        try octal(block[136..148], 0);
        block[156] = flag;
        // Libarchive requires a nonempty ustar link field before applying pax linkpath.
        if (flag == '2') @memcpy(block[157..161], "link");
        @memcpy(block[257..265], "ustar\x0000");
        @memset(block[148..156], ' ');
        var sum: u64 = 0;
        for (block) |byte| sum += byte;
        try octal(block[148..155], sum);
        try self.push(&block);
    }

    fn writeBody(self: *Stream, io: std.Io, body: content.Body) content.Error!void {
        std.debug.assert(body.length <= body.source.size());
        var buffer: [64 << 10]u8 = undefined; // SAFETY: read fills each emitted slice.
        var offset: u64 = 0;
        while (offset < body.length) {
            const count = std.math.cast(usize, @min(buffer.len, body.length - offset)) orelse
                return error.ContentLimit;
            try body.source.read(io, body.offset + offset, buffer[0..count]);
            try self.push(buffer[0..count]);
            offset += count;
        }
        try self.zeros(tar.padding(body.length));
    }
};

fn octal(field: []u8, number: u64) content.Error!void {
    std.debug.assert(field.len > 1);
    var value = number;
    field[field.len - 1] = 0;
    var i = field.len - 1;
    while (i > 0) {
        i -= 1;
        field[i] = '0' + (std.math.cast(u8, value & 7) orelse return error.ContentInvalid);
        value >>= 3;
    }
    if (value != 0) return error.ContentLimit;
}

fn record(arena: std.mem.Allocator, key: []const u8, value: []const u8) content.Error![]const u8 {
    std.debug.assert(key.len > 0);
    const body_length = key.len + value.len + 3;
    var length = body_length + 1;
    for (0..20) |_| {
        var digits: usize = 1;
        var rest = length;
        while (rest >= 10) : (rest /= 10) digits += 1;
        const next = body_length + digits;
        if (next == length) return arena.print("{d} {s}={s}\n", .{ length, key, value });
        length = next;
    }
    return error.ContentLimit;
}
