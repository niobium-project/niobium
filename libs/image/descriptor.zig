//! Fixed image references embedded in a native section; payload uses standard content formats.

const std = @import("std");
const image = @import("root.zig");
const stream = @import("stream.zig");

pub const size = 256;
pub const template_magic = "NIOTMP02";
pub const product_magic = "NIOIMG02";
pub const Descriptor = struct {
    template_bytes: u64,
    prefix_bytes: u64,
    template_sha256: [32]u8,
    program: image.Range,
    program_sha256: [32]u8,
    payload: image.Range,
    payload_sha256: [32]u8,
    native_prefix_sha256: [32]u8,
    native_prefix_profile: u32 = 1,
};

pub fn checkTemplate(bytes: *const [size]u8) image.Error!void {
    if (!std.mem.eql(u8, bytes, &image.templateSlot())) return error.ImageInvalid;
}

pub fn encode(value: Descriptor) [size]u8 {
    var bytes: [size]u8 = @splat(0);
    @memcpy(bytes[0..8], product_magic);
    std.mem.writeInt(u32, bytes[8..12], 2, .little);
    std.mem.writeInt(u32, bytes[12..16], size, .little);
    std.mem.writeInt(u64, bytes[16..24], value.template_bytes, .little);
    std.mem.writeInt(u64, bytes[24..32], value.program.offset, .little);
    std.mem.writeInt(u64, bytes[32..40], value.program.length, .little);
    std.mem.writeInt(u64, bytes[40..48], value.payload.offset, .little);
    std.mem.writeInt(u64, bytes[48..56], value.payload.length, .little);
    @memcpy(bytes[64..96], &value.template_sha256);
    @memcpy(bytes[96..128], &value.program_sha256);
    @memcpy(bytes[128..160], &value.payload_sha256);
    std.mem.writeInt(u64, bytes[160..168], value.prefix_bytes, .little);
    @memcpy(bytes[168..200], &value.native_prefix_sha256);
    std.mem.writeInt(u32, bytes[200..204], value.native_prefix_profile, .little);
    return bytes;
}

pub fn decode(bytes: *const [size]u8) image.Error!Descriptor {
    if (!std.mem.eql(u8, bytes[0..8], product_magic)) return error.ImageMissing;
    if (std.mem.readInt(u32, bytes[8..12], .little) != 2) return error.ImageUnsupported;
    if (std.mem.readInt(u32, bytes[12..16], .little) != size) return error.ImageInvalid;
    for (bytes[56..64]) |byte| if (byte != 0) return error.ImageInvalid;
    if (std.mem.readInt(u32, bytes[200..204], .little) != 1) return error.ImageUnsupported;
    for (bytes[204..]) |byte| if (byte != 0) return error.ImageInvalid;
    return .{
        .template_bytes = std.mem.readInt(u64, bytes[16..24], .little),
        .prefix_bytes = std.mem.readInt(u64, bytes[160..168], .little),
        .program = .{
            .offset = std.mem.readInt(u64, bytes[24..32], .little),
            .length = std.mem.readInt(u64, bytes[32..40], .little),
        },
        .payload = .{
            .offset = std.mem.readInt(u64, bytes[40..48], .little),
            .length = std.mem.readInt(u64, bytes[48..56], .little),
        },
        .template_sha256 = bytes[64..96].*,
        .program_sha256 = bytes[96..128].*,
        .payload_sha256 = bytes[128..160].*,
        .native_prefix_sha256 = bytes[168..200].*,
    };
}

pub fn ranges(value: Descriptor, layout: image.native.Layout, source_size: u64) image.Error!void {
    std.debug.assert(layout.slot.length == size);
    if (value.native_prefix_profile != 1) return error.ImageUnsupported;
    if (value.prefix_bytes > value.template_bytes or value.prefix_bytes < layout.protected_end) {
        return error.ImageInvalid;
    }
    if (value.program.offset != try stream.alignOffset(value.prefix_bytes, 16)) {
        return error.ImageInvalid;
    }
    if (value.payload.offset != try stream.alignOffset(try value.program.end(), 16)) {
        return error.ImageInvalid;
    }
    const end = try value.payload.end();
    if (end > source_size) return error.ImageInvalid;
    if (layout.signature.length > 0 and end > layout.signature.offset) return error.ImageInvalid;
}
