//! Byte-exact pure tar fixtures shared by parser and extraction tests.

const std = @import("std");
const tar = @import("root.zig");

pub const Tar = struct {
    gpa: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,

    pub fn deinit(t: *Tar) void {
        t.bytes.deinit(t.gpa);
    }

    /// Raw header: any typeflag, any path (split into prefix/name when longer than 100 bytes).
    pub fn header(t: *Tar, flag: u8, name: []const u8, size: u64) !void {
        var block: [tar.block_len]u8 = @splat(0);
        if (name.len <= 100) {
            @memcpy(block[0..name.len], name);
        } else {
            const split = std.mem.findScalarLast(
                u8,
                name[0..@min(name.len, 156)],
                '/',
            ) orelse return error.NameTooLong;
            if (name.len - split - 1 > 100) return error.NameTooLong;
            @memcpy(block[345..][0..split], name[0..split]);
            @memcpy(block[0 .. name.len - split - 1], name[split + 1 ..]);
        }
        writeOctal(block[100..108], 0o644);
        writeOctal(block[108..116], 0);
        writeOctal(block[116..124], 0);
        writeOctal(block[124..136], size);
        writeOctal(block[136..148], 0);
        block[156] = flag;
        @memcpy(block[257..265], "ustar\x0000");
        @memset(block[148..156], ' ');
        var sum: u64 = 0;
        for (block) |byte| sum += byte;
        writeOctal(block[148..155], sum);
        try t.bytes.appendSlice(t.gpa, &block);
    }

    pub fn data(t: *Tar, contents: []const u8) !void {
        try t.bytes.appendSlice(t.gpa, contents);
        try t.bytes.appendNTimes(t.gpa, 0, try small(tar.padding(contents.len)));
    }

    pub fn file(t: *Tar, name: []const u8, contents: []const u8) !void {
        try t.header('0', name, contents.len);
        try t.data(contents);
    }

    pub fn dir(t: *Tar, name: []const u8) !void {
        try t.header('5', name, 0);
    }

    pub fn pax(t: *Tar, records: []const u8) !void {
        try t.header('x', "PaxHeader", records.len);
        try t.data(records);
    }

    /// A pax header carrying one `path` record, with the self-referential length computed.
    pub fn paxPath(t: *Tar, value: []const u8) !void {
        const body = " path=".len + value.len + 1;
        var len = body + 1;
        while (std.math.log10_int(len) + 1 + body != len) len += 1;
        var buffer: [2048]u8 = undefined; // SAFETY: written by bufPrint.
        try t.pax(try std.fmt.bufPrint(&buffer, "{d} path={s}\n", .{ len, value }));
    }

    pub fn end(t: *Tar) !void {
        try t.bytes.appendNTimes(t.gpa, 0, tar.block_len * 2);
    }
};

fn writeOctal(out: []u8, value: u64) void {
    @memset(out, '0');
    var rest = value;
    var index = out.len - 1;
    out[index] = 0;
    while (index > 0) {
        index -= 1;
        out[index] = "01234567"[rest % 8];
        rest /= 8;
    }
}

fn small(n: u64) error{Overflow}!u21 {
    return std.math.cast(u21, n) orelse error.Overflow;
}
