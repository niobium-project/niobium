//! PE32+ image parsing; Authenticode is finalized after appended product data.

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
    const pe = try integer(u32, io, source, 0x3c);
    if (pe > limits.native_header_bytes) return error.ImageLimit;
    if (try integer(u32, io, source, pe) != 0x4550) return error.ImageInvalid;
    const count = try integer(u16, io, source, pe + 6);
    if (count == 0 or count > limits.native_sections) return error.ImageLimit;
    const optional: u64 = @as(u64, pe) + 24;
    if (try integer(u16, io, source, optional) != 0x20b) return error.ImageUnsupported;
    const optional_size = try integer(u16, io, source, pe + 20);
    if (optional_size < 152) return error.ImageInvalid;
    const table = optional + optional_size;
    var layout: native.Layout = .{
        .format = .pe,
        .cpu = switch (try integer(u16, io, source, pe + 4)) {
            0x8664 => .x86_64,
            0xaa64 => .aarch64,
            else => return error.ImageUnsupported,
        },
        .copy_length = source.size(),
        .pe_checksum = optional + 64,
        .signature_command = optional + 144,
        .section_count = count,
    };
    try native.protect(&layout, source, .{ .offset = 0, .length = table + @as(u64, count) * 40 });
    layout.tables = try arena.dupe(image.Range, &.{.{
        .offset = 0,
        .length = layout.protected_end,
    }});
    var code: std.ArrayList(image.Range) = .empty;
    for (0..count) |index| {
        const position = table + index * 40;
        var name: [8]u8 = undefined; // SAFETY: read fills the section name.
        try source.read(io, position, &name);
        const range: image.Range = .{
            .offset = try integer(u32, io, source, position + 20),
            .length = try integer(u32, io, source, position + 16),
        };
        try native.protect(&layout, source, range);
        const flags = try integer(u32, io, source, position + 36);
        if (flags & 0x20000000 != 0) {
            if (flags & 0x80000000 != 0) return error.ImageUnsupported;
            try code.append(arena, range);
        }
        if (native.name(&name, ".nbprod")) {
            if (flags & 0x20000000 != 0 or range.length < image.descriptor.size) {
                return error.ImageInvalid;
            }
            if (try integer(u32, io, source, position + 8) != image.descriptor.size) {
                return error.ImageInvalid;
            }
            try native.addSlot(&layout, .{
                .offset = range.offset,
                .length = image.descriptor.size,
            });
        }
    }
    try certificates(io, source, &layout, optional, optional_size);
    try symbols(arena, io, source, &layout, pe);
    layout.code = code.items;
    return layout;
}

fn certificates(
    io: std.Io,
    source: image.Source,
    layout: *native.Layout,
    optional: u64,
    optional_size: u16,
) image.Error!void {
    const directories = try integer(u32, io, source, optional + 108);
    if (directories < 5 or directories > 16 or optional_size < 112 + directories * 8) {
        return error.ImageInvalid;
    }
    layout.signature = .{
        .offset = try integer(u32, io, source, layout.signature_command),
        .length = try integer(u32, io, source, layout.signature_command + 4),
    };
    if (layout.signature.length > 0) {
        if (try layout.signature.end() != source.size()) return error.ImageInvalid;
        if (layout.signature.offset < layout.protected_end) return error.ImageInvalid;
        layout.copy_length = layout.signature.offset;
    } else if (layout.signature.offset != 0) return error.ImageInvalid;
}

fn symbols(
    arena: std.mem.Allocator,
    io: std.Io,
    source: image.Source,
    layout: *native.Layout,
    pe: u64,
) image.Error!void {
    const offset = try integer(u32, io, source, pe + 12);
    const count = try integer(u32, io, source, pe + 16);
    if (offset == 0) {
        if (count != 0) return error.ImageInvalid;
        return;
    }
    const table: image.Range = .{ .offset = offset, .length = @as(u64, count) * 18 };
    try native.protect(layout, source, table);
    const strings_offset = try table.end();
    const strings: image.Range = .{
        .offset = strings_offset,
        .length = try integer(u32, io, source, strings_offset),
    };
    if (strings.length < 4) return error.ImageInvalid;
    try native.protect(layout, source, strings);
    layout.tables = try arena.dupe(image.Range, &.{ layout.tables[0], table, strings });
}
