//! ELF64 little-endian executable templates retain every section and program header.

const std = @import("std");
const contracts = @import("contracts");
const image = @import("root.zig");
const native = @import("native.zig");
const integer = @import("stream.zig").integer;

pub fn inspect(
    arena: std.mem.Allocator,
    io: std.Io,
    source: image.Source,
    limits: contracts.Limits,
) image.Error!native.Layout {
    var header: [64]u8 = undefined; // SAFETY: read fills the ELF header.
    try source.read(io, 0, &header);
    if (header[4] != 2 or header[5] != 1 or header[6] != 1) return error.ImageUnsupported;
    const kind = try integer(u16, io, source, 16);
    if (kind != 2 and kind != 3) return error.ImageUnsupported;
    var layout: native.Layout = .{
        .format = .elf,
        .cpu = switch (try integer(u16, io, source, 18)) {
            62 => .x86_64,
            183 => .aarch64,
            else => return error.ImageUnsupported,
        },
        .copy_length = source.size(),
    };
    const offset = try integer(u64, io, source, 40);
    const count = try integer(u16, io, source, 60);
    if (count == 0 or count > limits.native_sections) return error.ImageLimit;
    layout.section_count = count;
    if (try integer(u16, io, source, 58) != 64) return error.ImageInvalid;
    try native.protect(&layout, source, .{ .offset = offset, .length = @as(u64, count) * 64 });
    const strings_index = try integer(u16, io, source, 62);
    if (strings_index >= count) return error.ImageInvalid;
    const strings = offset + @as(u64, strings_index) * 64;
    const strings_offset = try integer(u64, io, source, strings + 24);
    const strings_size = try integer(u64, io, source, strings + 32);
    if (strings_size > limits.native_header_bytes) return error.ImageLimit;
    try native.protect(&layout, source, .{ .offset = strings_offset, .length = strings_size });
    var code: std.ArrayList(image.Range) = .empty;
    for (0..count) |index| {
        const item = offset + index * 64;
        const section_type = try integer(u32, io, source, item + 4);
        if (section_type == 8) continue;
        const flags = try integer(u64, io, source, item + 8);
        if (flags & 5 == 5) return error.ImageUnsupported;
        const range: image.Range = .{
            .offset = try integer(u64, io, source, item + 24),
            .length = try integer(u64, io, source, item + 32),
        };
        try native.protect(&layout, source, range);
        if (flags & 4 != 0) try code.append(arena, range);
        const name_index = try integer(u32, io, source, item);
        if (name_index >= strings_size) return error.ImageInvalid;
        var name: [8]u8 = @splat(0);
        const length = std.math.cast(usize, @min(8, strings_size - name_index)) orelse
            return error.ImageInvalid;
        try source.read(io, strings_offset + name_index, name[0..length]);
        if (native.name(&name, ".nbprod")) {
            if (flags & 4 != 0 or flags & 2 == 0) return error.ImageInvalid;
            try native.addSlot(&layout, range);
        }
    }
    try programHeaders(io, source, &layout, limits);
    layout.tables = try arena.dupe(image.Range, &.{
        .{ .offset = 0, .length = 64 },
        .{ .offset = offset, .length = @as(u64, count) * 64 },
        .{ .offset = strings_offset, .length = strings_size },
        .{
            .offset = try integer(u64, io, source, 32),
            .length = @as(u64, try integer(u16, io, source, 56)) * 56,
        },
    });
    layout.code = code.items;
    return layout;
}

fn programHeaders(
    io: std.Io,
    source: image.Source,
    layout: *native.Layout,
    limits: contracts.Limits,
) image.Error!void {
    const offset = try integer(u64, io, source, 32);
    const count = try integer(u16, io, source, 56);
    if (count > limits.native_sections) return error.ImageLimit;
    if (try integer(u16, io, source, 54) != 56) return error.ImageInvalid;
    try native.protect(layout, source, .{ .offset = offset, .length = @as(u64, count) * 56 });
    for (0..count) |index| {
        const position = offset + index * 56;
        const flags = try integer(u32, io, source, position + 4);
        if (flags & 3 == 3) return error.ImageUnsupported;
        try native.protect(layout, source, .{
            .offset = try integer(u64, io, source, position + 8),
            .length = try integer(u64, io, source, position + 32),
        });
    }
}
