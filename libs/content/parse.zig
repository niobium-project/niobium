//! Bounded, positional POSIX tar parser. Payload bytes stay in borrowed backing storage.

const std = @import("std");
const contracts = @import("contracts");
const tar = @import("tar");
const content = @import("root.zig");
const normalize = @import("transform.zig").normalize;

const Header = struct {
    flag: u8,
    name: []const u8,
    link: []const u8,
    mode: u16,
    size: u64,
};

const Pax = struct {
    path: ?[]const u8 = null,
    link: ?[]const u8 = null,
    size: ?u64 = null,
};

pub fn parse(
    arena: std.mem.Allocator,
    io: std.Io,
    source: content.Source,
    limits: contracts.Limits,
) content.Error!content.Tree {
    std.debug.assert(limits.path_bytes > 0);
    if (source.size() > limits.expanded_bytes) return error.ContentLimit;
    var parser: Parser = .{ .arena = arena, .io = io, .source = source, .limits = limits };
    try parser.run();
    return normalize(arena, parser.entries.items, limits);
}

const Parser = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    source: content.Source,
    limits: contracts.Limits,
    offset: u64 = 0,
    header_count: u64 = 0,
    entries: std.ArrayList(content.Entry) = .empty,

    fn run(self: *Parser) content.Error!void {
        std.debug.assert(self.offset == 0);
        var pending: ?Pax = null;
        while (self.offset < self.source.size()) {
            self.header_count += 1;
            if (self.header_count > (@as(u64, self.limits.files_per_artifact) + 1) * 2 + 2) {
                return error.ContentLimit;
            }
            var block: [tar.block_len]u8 = undefined; // SAFETY: read fills the header.
            try self.source.read(self.io, self.offset, &block);
            self.offset += tar.block_len;
            if (tar.isZero(&block)) {
                if (pending != null) return error.ContentInvalid;
                return self.trailer();
            }
            const header = try readHeader(self.arena, &block);
            if (header.flag == 'x' or header.flag == 'g') {
                if (pending != null) return error.ContentInvalid;
                const pax = try self.extended(header.size);
                if (header.flag == 'x') pending = pax else {
                    if (pax.path != null or pax.link != null or pax.size != null) {
                        return error.ContentUnsupported;
                    }
                }
                continue;
            }
            try self.entry(header, pending orelse .{});
            pending = null;
        }
        return error.ContentInvalid;
    }

    fn extended(self: *Parser, size: u64) content.Error!Pax {
        std.debug.assert(self.offset >= tar.block_len);
        if (size > self.limits.json_string_bytes or size > 64 << 10) return error.ContentLimit;
        const length = std.math.cast(usize, size) orelse return error.ContentLimit;
        const bytes = try self.arena.alloc(u8, length);
        try self.source.read(self.io, self.offset, bytes);
        try self.skip(size);
        return readPax(bytes);
    }

    fn entry(self: *Parser, header: Header, pax: Pax) content.Error!void {
        std.debug.assert(self.offset >= tar.block_len);
        const kind: content.Kind = switch (header.flag) {
            0, '0' => .file,
            '5' => .directory,
            '2' => .symlink,
            else => return error.ContentUnsupported,
        };
        const size = pax.size orelse header.size;
        if (size > self.limits.archive_entry_bytes) return error.ContentLimit;
        if (kind != .file and size != 0) return error.ContentInvalid;
        const name = try content.names.sourceName(
            pax.path orelse header.name,
            kind == .directory,
            self.limits,
        );
        const link = pax.link orelse header.link;
        if (kind != .symlink and link.len > 0) return error.ContentInvalid;
        if (name.len > 0) {
            if (self.entries.items.len >= self.limits.files_per_artifact) return error.ContentLimit;
            try self.entries.append(self.arena, .{
                .path = name,
                .kind = kind,
                .mode = header.mode,
                .link_target = link,
                .body = .{ .source = self.source, .offset = self.offset, .length = size },
            });
        }
        try self.skip(size);
    }

    fn skip(self: *Parser, size: u64) content.Error!void {
        std.debug.assert(self.offset <= self.source.size());
        const end = std.math.add(u64, self.offset, size) catch return error.ContentInvalid;
        const padded = std.math.add(u64, end, tar.padding(size)) catch return error.ContentInvalid;
        if (padded > self.source.size()) return error.ContentInvalid;
        var padding: [tar.block_len]u8 = undefined; // SAFETY: read fills the checked slice.
        const length = std.math.cast(usize, padded - end) orelse return error.ContentInvalid;
        try self.source.read(self.io, end, padding[0..length]);
        for (padding[0..length]) |byte| if (byte != 0) return error.ContentInvalid;
        self.offset = padded;
    }

    fn trailer(self: *Parser) content.Error!void {
        std.debug.assert(self.offset >= tar.block_len);
        if (self.source.size() - self.offset < tar.block_len) return error.ContentInvalid;
        if (self.source.size() % tar.block_len != 0) return error.ContentInvalid;
        var block: [tar.block_len]u8 = undefined; // SAFETY: read fills each block.
        while (self.offset < self.source.size()) : (self.offset += tar.block_len) {
            try self.source.read(self.io, self.offset, &block);
            if (!tar.isZero(&block)) return error.ContentInvalid;
        }
    }
};

fn field(bytes: []const u8) []const u8 {
    const length = std.mem.findScalar(u8, bytes, 0) orelse bytes.len;
    return bytes[0..length];
}

fn readHeader(arena: std.mem.Allocator, block: *const [tar.block_len]u8) content.Error!Header {
    std.debug.assert(block.len == tar.block_len);
    var checksum: u64 = 0;
    for (block, 0..) |byte, i| checksum += if (i >= 148 and i < 156) ' ' else byte;
    if ((tar.parseOctal(block[148..156]) catch return error.ContentInvalid) != checksum) {
        return error.ContentInvalid;
    }
    const posix = std.mem.eql(u8, block[257..265], "ustar\x0000");
    if (!posix and !std.mem.eql(u8, block[257..265], "ustar  \x00")) {
        return error.ContentUnsupported;
    }
    const prefix = if (posix) field(block[345..500]) else "";
    const name = field(block[0..100]);
    const joined = if (prefix.len == 0)
        try arena.dupe(u8, name)
    else
        try std.mem.concat(arena, u8, &.{ prefix, "/", name });
    const mode = tar.parseOctal(block[100..108]) catch return error.ContentInvalid;
    if (mode > 0o777) return error.ContentUnsupported;
    return .{
        .flag = block[156],
        .name = joined,
        .link = try arena.dupe(u8, field(block[157..257])),
        .mode = std.math.cast(u16, mode) orelse return error.ContentInvalid,
        .size = tar.parseOctal(block[124..136]) catch return error.ContentInvalid,
    };
}

fn readPax(bytes: []const u8) content.Error!Pax {
    std.debug.assert(bytes.len <= 64 << 10);
    var result: Pax = .{};
    var rest = bytes;
    while (rest.len > 0) {
        const space = std.mem.findScalar(u8, rest, ' ') orelse return error.ContentInvalid;
        if (!decimal(rest[0..space])) return error.ContentInvalid;
        const length = std.fmt.parseInt(usize, rest[0..space], 10) catch
            return error.ContentInvalid;
        if (length <= space + 1 or length > rest.len) return error.ContentInvalid;
        if (rest[length - 1] != '\n') return error.ContentInvalid;
        const record = rest[space + 1 .. length - 1];
        const equal = std.mem.findScalar(u8, record, '=') orelse return error.ContentInvalid;
        const key = record[0..equal];
        const value = record[equal + 1 ..];
        if (std.mem.eql(u8, key, "path")) {
            if (result.path != null) return error.ContentInvalid;
            result.path = value;
        } else if (std.mem.eql(u8, key, "linkpath")) {
            if (result.link != null) return error.ContentInvalid;
            result.link = value;
        } else if (std.mem.eql(u8, key, "size")) {
            if (result.size != null) return error.ContentInvalid;
            if (!decimal(value)) return error.ContentInvalid;
            result.size = std.fmt.parseInt(u64, value, 10) catch return error.ContentInvalid;
        } else if (!ignoredKey(key)) return error.ContentUnsupported;
        rest = rest[length..];
    }
    return result;
}

fn decimal(bytes: []const u8) bool {
    if (bytes.len == 0) return false;
    for (bytes) |byte| if (byte < '0' or byte > '9') return false;
    return true;
}

fn ignoredKey(key: []const u8) bool {
    for ([_][]const u8{ "uid", "gid", "uname", "gname", "mtime", "atime", "ctime" }) |name| {
        if (std.mem.eql(u8, key, name)) return true;
    }
    return false;
}
