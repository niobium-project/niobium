//! Native format dispatch and only the header edits permitted by the image contract.

const std = @import("std");
const contracts = @import("contracts");
const image = @import("root.zig");
const stream = @import("stream.zig");

pub const Layout = struct {
    format: image.Format,
    cpu: image.Cpu,
    slot: image.Range = .{ .offset = 0, .length = 0 },
    code: []const image.Range = &.{},
    tables: []const image.Range = &.{},
    section_count: u32 = 0,
    protected_end: u64 = 0,
    copy_length: u64,
    signature: image.Range = .{ .offset = 0, .length = 0 },
    signature_command: u64 = 0,
    linkedit_command: u64 = 0,
    linkedit_offset: u64 = 0,
    linkedit_vmaddr: u64 = 0,
    other_vm_end: u64 = 0,
    pe_checksum: u64 = 0,

    pub fn signatureAlignment(layout: Layout) u64 {
        return switch (layout.format) {
            .elf => 1,
            .pe => 8,
            .macho => 16,
        };
    }
};

pub fn inspect(
    arena: std.mem.Allocator,
    io: std.Io,
    source: image.Source,
    limits: contracts.Limits,
) image.Error!Layout {
    std.debug.assert(limits.native_sections > 0);
    if (source.size() > limits.native_image_bytes) return error.ImageLimit;
    const magic = try stream.integer(u32, io, source, 0);
    const layout = switch (magic) {
        0xfeedfacf => try @import("macho.zig").inspect(arena, io, source, limits),
        0x464c457f => try @import("elf.zig").inspect(arena, io, source, limits),
        else => if (magic & 0xffff == 0x5a4d)
            try @import("pe.zig").inspect(arena, io, source, limits)
        else
            return error.ImageUnsupported,
    };
    if (layout.slot.length != image.descriptor.size) return error.ImageMissing;
    if (try layout.slot.end() > layout.protected_end) return error.ImageInvalid;
    if (layout.protected_end > layout.copy_length) return error.ImageInvalid;
    if (layout.code.len == 0) return error.ImageInvalid;
    for (layout.code) |range| if (try overlap(layout.slot, range)) return error.ImageInvalid;
    for (layout.tables) |range| if (try overlap(layout.slot, range)) return error.ImageInvalid;
    return layout;
}

fn overlap(a: image.Range, b: image.Range) image.Error!bool {
    if (a.length == 0 or b.length == 0) return false;
    return a.offset < try b.end() and b.offset < try a.end();
}

pub fn finalize(
    io: std.Io,
    output: std.Io.File,
    layout: Layout,
    signature_offset: u64,
    final_length: u64,
) image.Error!void {
    std.debug.assert(final_length >= signature_offset);
    if (layout.format == .pe) {
        try stream.set(u32, io, output, layout.pe_checksum, 0);
        try stream.set(u64, io, output, layout.signature_command, 0);
    }
    if (layout.format != .macho) return;
    try stream.set(
        u32,
        io,
        output,
        layout.signature_command + 8,
        std.math.cast(u32, signature_offset) orelse return error.ImageLimit,
    );
    const linkedit_size = final_length - layout.linkedit_offset;
    const virtual_size = try stream.alignOffset(linkedit_size, 16384);
    if (virtual_size > std.math.maxInt(u64) - layout.linkedit_vmaddr) return error.ImageLimit;
    try stream.set(u64, io, output, layout.linkedit_command + 48, linkedit_size);
    try stream.set(
        u64,
        io,
        output,
        layout.linkedit_command + 32,
        virtual_size,
    );
}

pub fn addSlot(layout: *Layout, slot: image.Range) image.Error!void {
    if (layout.slot.length != 0 or slot.length != image.descriptor.size) return error.ImageInvalid;
    layout.slot = slot;
}

pub fn protect(layout: *Layout, source: image.Source, range: image.Range) image.Error!void {
    const end = try range.end();
    if (end > source.size()) return error.ImageInvalid;
    layout.protected_end = @max(layout.protected_end, end);
}

pub fn name(bytes: []const u8, expected: []const u8) bool {
    const length = std.mem.findScalar(u8, bytes, 0) orelse bytes.len;
    return std.mem.eql(u8, bytes[0..length], expected);
}
