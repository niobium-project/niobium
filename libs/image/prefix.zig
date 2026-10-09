//! Stable measurement of every native prefix byte except the narrowly mutable packaging fields.
const std = @import("std");
const contracts = @import("contracts");
const image = @import("root.zig");

pub const profile: u32 = 1;
const domain = "niobium.native-prefix\x00";
const Masks = struct { ranges: [4]image.Range, count: usize };

pub fn measure(
    io: std.Io,
    source: image.Source,
    layout: image.native.Layout,
    length: u64,
    limits: contracts.Limits,
) image.Error!contracts.Digest {
    std.debug.assert(limits.native_image_bytes > 0);
    if (length == 0 or length > source.size() or length > limits.native_image_bytes)
        return error.ImageLimit;
    const masks = try mutableFields(layout, length, limits);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(domain);
    hash.update(@tagName(layout.format));
    hash.update("\x00");
    hash.update(@tagName(layout.cpu));
    hash.update("\x00");
    var identity: [12]u8 = undefined; // SAFETY: both integers initialize the entire domain suffix.
    std.mem.writeInt(u32, identity[0..4], profile, .little);
    std.mem.writeInt(u64, identity[4..12], length, .little);
    hash.update(&identity);
    var buffer: [64 << 10]u8 = undefined; // SAFETY: source fills each measured chunk.
    var offset: u64 = 0;
    while (offset < length) {
        const count = std.math.cast(usize, @min(buffer.len, length - offset)) orelse
            return error.ImageLimit;
        try source.read(io, offset, buffer[0..count]);
        for (masks.ranges[0..masks.count]) |range| {
            const start = @max(offset, range.offset);
            const end = @min(offset + count, try range.end());
            if (start >= end) continue;
            const first = std.math.cast(usize, start - offset) orelse return error.ImageInvalid;
            const last = std.math.cast(usize, end - offset) orelse return error.ImageInvalid;
            @memset(buffer[first..last], 0);
        }
        hash.update(buffer[0..count]);
        offset += count;
    }
    return hash.finalResult();
}

fn mutableFields(
    layout: image.native.Layout,
    length: u64,
    limits: contracts.Limits,
) image.Error!Masks {
    if (layout.slot.length != image.descriptor.size or layout.tables.len == 0)
        return error.ImageInvalid;
    if (layout.code.len > limits.native_sections or layout.tables.len > limits.native_sections)
        return error.ImageLimit;
    const header = layout.tables[0];
    if (header.offset != 0 or header.length > limits.native_header_bytes or
        try header.end() > length) return error.ImageInvalid;
    for (layout.tables) |table| {
        if (try overlaps(layout.slot, table)) return error.ImageInvalid;
    }
    var masks: Masks = .{ .ranges = @splat(.{ .offset = 0, .length = 0 }), .count = 1 };
    masks.ranges[0] = layout.slot;
    switch (layout.format) {
        .elf => {},
        .pe => {
            masks.ranges[1] = try field(layout.pe_checksum, 0, 4);
            masks.ranges[2] = try field(layout.signature_command, 0, 8);
            masks.count = 3;
        },
        .macho => {
            masks.ranges[1] = try field(layout.signature_command, 8, 8);
            masks.ranges[2] = try field(layout.linkedit_command, 32, 8);
            masks.ranges[3] = try field(layout.linkedit_command, 48, 8);
            masks.count = 4;
        },
    }
    for (masks.ranges[0..masks.count], 0..) |range, index| {
        const end = try range.end();
        if (end > length) return error.ImageInvalid;
        if (index != 0 and end > try header.end()) return error.ImageInvalid;
        for (layout.code) |code| if (try overlaps(range, code)) return error.ImageInvalid;
        for (masks.ranges[0..index]) |previous| {
            if (try overlaps(range, previous)) return error.ImageInvalid;
        }
    }
    return masks;
}

fn field(base: u64, relative: u64, length: u64) image.Error!image.Range {
    return .{
        .offset = std.math.add(u64, base, relative) catch return error.ImageInvalid,
        .length = length,
    };
}

fn overlaps(a: image.Range, b: image.Range) image.Error!bool {
    if (a.length == 0 or b.length == 0) return false;
    return a.offset < try b.end() and b.offset < try a.end();
}

test {
    _ = @import("prefix_test.zig");
}
