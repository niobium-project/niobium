//! Host-independent assembly of complete native templates and referenced product content.

const std = @import("std");
const contracts = @import("contracts");
const content = @import("content");
pub const native = @import("native.zig");
pub const descriptor = @import("descriptor.zig");
pub const fixture = @import("fixture.zig");
pub const prefix = @import("prefix.zig");
pub const verifyAdhoc = @import("signature.zig").verify;
const stream = @import("stream.zig");

pub const Source = content.Source;
pub const Body = content.Body;
pub const Descriptor = descriptor.Descriptor;
pub const Error = content.Error || error{
    ImageInvalid,
    ImageUnsupported,
    ImageMissing,
    ImageLimit,
    ImageDigest,
    ImageWriteFailed,
    SignatureInvalid,
    SignatureUnsupported,
    SignatureDigest,
};
pub const Format = enum { elf, pe, macho };
pub const Cpu = enum { x86_64, aarch64 };
pub const Range = struct {
    offset: u64,
    length: u64,

    pub fn end(range: Range) Error!u64 {
        return std.math.add(u64, range.offset, range.length) catch error.ImageInvalid;
    }
};

pub const Assembly = struct {
    descriptor: Descriptor,
    format: Format,
    cpu: Cpu,
    /// Mach-O output has a relocated stale signature and requires final signing.
    requires_signing: bool,
    bytes: u64,
};

pub fn templateSlot() [descriptor.size]u8 {
    var slot: [descriptor.size]u8 = @splat(0);
    @memcpy(slot[0..8], descriptor.template_magic);
    std.mem.writeInt(u32, slot[8..12], 2, .little);
    std.mem.writeInt(u32, slot[12..16], descriptor.size, .little);
    std.mem.writeInt(u32, slot[200..204], prefix.profile, .little);
    return slot;
}

pub fn assemble(
    arena: std.mem.Allocator,
    io: std.Io,
    template: Source,
    program: Body,
    payload: Body,
    output: std.Io.File,
    limits: contracts.Limits,
) Error!Assembly {
    std.debug.assert(limits.native_sections > 0);
    if ((output.stat(io) catch return error.ImageWriteFailed).size != 0) return error.ImageInvalid;
    if (template.size() > limits.native_image_bytes) return error.ImageLimit;
    const template_hash = try stream.copy(io, .{
        .source = template,
        .length = template.size(),
    }, output, 0);
    const captured: Source = .{ .file = .{ .handle = output, .length = template.size() } };
    const layout = try native.inspect(arena, io, captured, limits);
    var slot: [descriptor.size]u8 = undefined; // SAFETY: read fills the reserved descriptor.
    try captured.read(io, layout.slot.offset, &slot);
    try descriptor.checkTemplate(&slot);
    const native_prefix = try prefix.measure(io, captured, layout, layout.copy_length, limits);
    const program_offset = try stream.alignOffset(layout.copy_length, 16);
    const program_end = std.math.add(u64, program_offset, program.length) catch
        return error.ImageLimit;
    const payload_offset = try stream.alignOffset(program_end, 16);
    const payload_end = std.math.add(u64, payload_offset, payload.length) catch
        return error.ImageLimit;
    const signature_offset = try stream.alignOffset(payload_end, layout.signatureAlignment());
    const signature_length = if (layout.format == .macho) layout.signature.length else 0;
    const final_length = std.math.add(u64, signature_offset, signature_length) catch
        return error.ImageLimit;
    if (final_length > limits.native_image_bytes) return error.ImageLimit;
    if (layout.format == .macho) {
        if (signature_offset > std.math.maxInt(u32)) return error.ImageLimit;
        try stream.move(io, output, layout.signature, signature_offset);
    }
    const value: Descriptor = .{
        .template_bytes = template.size(),
        .template_sha256 = template_hash,
        .prefix_bytes = layout.copy_length,
        .native_prefix_sha256 = native_prefix,
        .program = .{ .offset = program_offset, .length = program.length },
        .program_sha256 = try stream.copy(io, program, output, program_offset),
        .payload = .{ .offset = payload_offset, .length = payload.length },
        .payload_sha256 = try stream.copy(io, payload, output, payload_offset),
    };
    try stream.zero(io, output, layout.copy_length, program_offset);
    try stream.zero(io, output, program_end, payload_offset);
    try stream.zero(io, output, payload_end, signature_offset);
    try native.finalize(io, output, layout, signature_offset, final_length);
    output.writePositionalAll(io, &descriptor.encode(value), layout.slot.offset) catch
        return error.ImageWriteFailed;
    output.setLength(io, final_length) catch return error.ImageWriteFailed;
    return .{
        .descriptor = value,
        .format = layout.format,
        .cpu = layout.cpu,
        .requires_signing = layout.format == .macho,
        .bytes = final_length,
    };
}

pub fn inspect(
    arena: std.mem.Allocator,
    io: std.Io,
    source: Source,
    limits: contracts.Limits,
) Error!Descriptor {
    std.debug.assert(limits.native_sections > 0);
    const layout = try native.inspect(arena, io, source, limits);
    var slot: [descriptor.size]u8 = undefined; // SAFETY: read initializes the complete slot.
    try source.read(io, layout.slot.offset, &slot);
    const value = try descriptor.decode(&slot);
    if (value.template_bytes > limits.native_image_bytes) return error.ImageLimit;
    try descriptor.ranges(value, layout, source.size());
    try stream.checkZero(io, source, value.prefix_bytes, value.program.offset);
    try stream.checkZero(io, source, try value.program.end(), value.payload.offset);
    const end = try value.payload.end();
    const tail = if (layout.signature.length > 0) layout.signature.offset else source.size();
    if (tail - end >= layout.signatureAlignment()) return error.ImageInvalid;
    try stream.checkZero(io, source, end, tail);
    return value;
}

pub fn verify(
    arena: std.mem.Allocator,
    io: std.Io,
    source: Source,
    limits: contracts.Limits,
) Error!Descriptor {
    std.debug.assert(limits.native_image_bytes > 0);
    const value = try inspect(arena, io, source, limits);
    const layout = try native.inspect(arena, io, source, limits);
    const native_hash = try prefix.measure(io, source, layout, value.prefix_bytes, limits);
    if (!std.mem.eql(u8, &native_hash, &value.native_prefix_sha256)) return error.ImageDigest;
    const program_hash = try stream.hash(io, .{
        .source = source,
        .offset = value.program.offset,
        .length = value.program.length,
    });
    const payload_hash = try stream.hash(io, .{
        .source = source,
        .offset = value.payload.offset,
        .length = value.payload.length,
    });
    if (!std.mem.eql(u8, &program_hash, &value.program_sha256) or
        !std.mem.eql(u8, &payload_hash, &value.payload_sha256)) return error.ImageDigest;
    return value;
}

test {
    _ = prefix;
    _ = @import("signature.zig");
    _ = @import("image_test.zig");
}
