//! Mach-O64 templates expand only the final __LINKEDIT segment before final signing.

const std = @import("std");
const contracts = @import("contracts");
const image = @import("root.zig");
const native = @import("native.zig");
const stream = @import("stream.zig");
const integer = stream.integer;

pub fn inspect(
    arena: std.mem.Allocator,
    io: std.Io,
    source: image.Source,
    limits: contracts.Limits,
) image.Error!native.Layout {
    if (try integer(u32, io, source, 12) != 2) return error.ImageUnsupported;
    var layout: native.Layout = .{
        .format = .macho,
        .cpu = switch (try integer(u32, io, source, 4)) {
            0x01000007 => .x86_64,
            0x0100000c => .aarch64,
            else => return error.ImageUnsupported,
        },
        .copy_length = source.size(),
    };
    const count = try integer(u32, io, source, 16);
    const size = try integer(u32, io, source, 20);
    if (count > limits.native_sections or size > limits.native_header_bytes) {
        return error.ImageLimit;
    }
    try native.protect(&layout, source, .{ .offset = 0, .length = @as(u64, size) + 32 });
    layout.tables = try arena.dupe(image.Range, &.{.{
        .offset = 0,
        .length = layout.protected_end,
    }});
    var code: std.ArrayList(image.Range) = .empty;
    var cursor: u64 = 32;
    for (0..count) |_| {
        const kind = try integer(u32, io, source, cursor);
        const length = try integer(u32, io, source, cursor + 4);
        if (length < 8 or length > @as(u64, size) + 32 - cursor) return error.ImageInvalid;
        if (kind == 0x19) {
            try segment(arena, io, source, &layout, &code, cursor, length, limits);
        } else if (kind == 0x1d) {
            if (length != 16 or layout.signature_command != 0) return error.ImageInvalid;
            layout.signature_command = cursor;
            layout.signature = .{
                .offset = try integer(u32, io, source, cursor + 8),
                .length = try integer(u32, io, source, cursor + 12),
            };
        } else try linkData(io, source, &layout, kind, cursor, length);
        cursor += length;
    }
    if (cursor != @as(u64, size) + 32 or layout.signature.length == 0 or
        layout.linkedit_command == 0) return error.ImageInvalid;
    if (try layout.signature.end() != source.size()) return error.ImageInvalid;
    if (layout.other_vm_end > layout.linkedit_vmaddr) return error.ImageInvalid;
    if (layout.signature.offset < layout.protected_end or
        layout.signature.offset < layout.linkedit_offset) return error.ImageInvalid;
    layout.copy_length = layout.signature.offset;
    layout.code = code.items;
    return layout;
}

fn segment(
    arena: std.mem.Allocator,
    io: std.Io,
    source: image.Source,
    layout: *native.Layout,
    code: *std.ArrayList(image.Range),
    offset: u64,
    length: u32,
    limits: contracts.Limits,
) image.Error!void {
    if (length < 72) return error.ImageInvalid;
    var name: [16]u8 = undefined; // SAFETY: read initializes the segment name.
    try source.read(io, offset + 8, &name);
    const file_range: image.Range = .{
        .offset = try integer(u64, io, source, offset + 40),
        .length = try integer(u64, io, source, offset + 48),
    };
    const protection = try integer(u32, io, source, offset + 60);
    if (protection & 6 == 6) return error.ImageUnsupported;
    const count = try integer(u32, io, source, offset + 64);
    if (count > limits.native_sections or count > (length - 72) / 80) return error.ImageLimit;
    if (count > limits.native_sections -| layout.section_count) return error.ImageLimit;
    layout.section_count += count;
    const vmaddr = try integer(u64, io, source, offset + 24);
    const vmsize = try integer(u64, io, source, offset + 32);
    const vmend = std.math.add(u64, vmaddr, vmsize) catch return error.ImageInvalid;
    if (native.name(&name, "__LINKEDIT")) {
        if (layout.linkedit_command != 0 or count != 0) return error.ImageInvalid;
        if (try file_range.end() != source.size()) return error.ImageInvalid;
        const pages4k = try stream.alignOffset(file_range.length, 4096);
        const pages16k = try stream.alignOffset(file_range.length, 16384);
        if (vmsize != pages4k and vmsize != pages16k) return error.ImageInvalid;
        layout.linkedit_command = offset;
        layout.linkedit_offset = file_range.offset;
        layout.linkedit_vmaddr = vmaddr;
    } else {
        layout.other_vm_end = @max(layout.other_vm_end, vmend);
        try native.protect(layout, source, file_range);
    }
    for (0..count) |index| {
        const position = offset + 72 + index * 80;
        var section_name: [16]u8 = undefined; // SAFETY: read fills section name bytes.
        try source.read(io, position, &section_name);
        const flags = try integer(u32, io, source, position + 64);
        if (flags & 0xff == 1 or flags & 0xff == 0xc or flags & 0xff == 0x12) continue;
        const range: image.Range = .{
            .offset = try integer(u32, io, source, position + 48),
            .length = try integer(u64, io, source, position + 40),
        };
        try native.protect(layout, source, range);
        if (flags & 0x80000400 != 0) try code.append(arena, range);
        if (native.name(&section_name, "__nbproduct")) {
            if (!native.name(&name, "__DATA") or protection & 4 != 0) return error.ImageInvalid;
            try native.addSlot(layout, range);
        }
    }
}

fn linkData(
    io: std.Io,
    source: image.Source,
    layout: *native.Layout,
    kind: u32,
    position: u64,
    length: u32,
) image.Error!void {
    switch (kind) {
        0x26, 0x29, 0x2b, 0x2e, 0x80000033, 0x80000034 => {
            if (length != 16) return error.ImageInvalid;
            try protectPair(io, source, layout, position + 8, 1);
        },
        0x2 => {
            if (length != 24) return error.ImageInvalid;
            try protectPair(io, source, layout, position + 8, 16);
            try protectPair(io, source, layout, position + 16, 1);
        },
        0xb => {
            if (length != 80) return error.ImageInvalid;
            for ([_]u64{ 32, 40, 48, 56, 64, 72 }, [_]u64{ 8, 56, 4, 4, 8, 8 }) |at, width| {
                try protectPair(io, source, layout, position + at, width);
            }
        },
        0x22, 0x80000022 => {
            if (length != 48) return error.ImageInvalid;
            for (0..5) |index| try protectPair(io, source, layout, position + 8 + index * 8, 1);
        },
        // These supported load commands reference only virtual addresses or inline bytes.
        0xc,
        0xd,
        0xe,
        0xf,
        0x18,
        0x80000018,
        0x8000001f,
        0x80000023,
        0x8000001c,
        0x1b,
        0x24,
        0x25,
        0x2a,
        0x2f,
        0x30,
        0x32,
        0x80000028,
        => {},
        else => return error.ImageUnsupported,
    }
}

fn protectPair(
    io: std.Io,
    source: image.Source,
    layout: *native.Layout,
    offset: u64,
    width: u64,
) image.Error!void {
    const count = try integer(u32, io, source, offset + 4);
    if (count == 0) return;
    try native.protect(layout, source, .{
        .offset = try integer(u32, io, source, offset),
        .length = @as(u64, count) * width,
    });
}
