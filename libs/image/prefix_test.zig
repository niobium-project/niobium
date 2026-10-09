//! Native-prefix measurements cover code, data and headers and permit only fixed masks.
const std = @import("std");
const image = @import("root.zig");
const prefix = @import("prefix.zig");
const io = std.testing.io;

test "N2-IMAGE-04 complete ELF prefix rejects code data and entrypoint tampering" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const file = try temp.dir.createFile(io, "setup", .{ .read = true });
    defer file.close(io);
    const template = image.fixture.elf();
    const assembled = try image.assemble(
        a,
        io,
        .{ .bytes = &template },
        .bytes("program"),
        .bytes("payload"),
        file,
        .{},
    );
    const source: image.Source = .{ .file = .{ .handle = file, .length = assembled.bytes } };
    const before = try image.verify(a, io, source, .{});
    try std.testing.expectEqualDeep(assembled.descriptor, before);
    for ([_]u64{ 128, 200, 24 }) |offset| {
        var byte: [1]u8 = undefined; // SAFETY: positional read initializes the changed byte.
        try source.read(io, offset, &byte);
        byte[0] ^= 1;
        try file.writePositionalAll(io, &byte, offset);
        try std.testing.expectError(error.ImageDigest, image.verify(a, io, source, .{}));
        byte[0] ^= 1;
        try file.writePositionalAll(io, &byte, offset);
    }
    const verified = try image.verify(a, io, source, .{});
    try std.testing.expectEqualDeep(before, verified);
}

fn layout(format: image.Format) image.native.Layout {
    return .{
        .format = format,
        .cpu = .x86_64,
        .slot = .{ .offset = 1024, .length = 256 },
        .code = &.{.{ .offset = 512, .length = 128 }},
        .tables = &.{.{ .offset = 0, .length = 512 }},
        .protected_end = 1280,
        .copy_length = 2048,
        .pe_checksum = 64,
        .signature_command = 256,
        .linkedit_command = 64,
    };
}

test "N2-IMAGE-04 packaging masks preserve PE and Mach-O measurements exactly" {
    for ([_]image.Format{ .pe, .macho }) |format| {
        const native = layout(format);
        var bytes: [2048]u8 = @splat(0x41);
        const source: image.Source = .{ .bytes = &bytes };
        const before = try prefix.measure(io, source, native, bytes.len, .{});
        @memset(bytes[1024..1280], 0x22);
        if (format == .pe) {
            @memset(bytes[64..68], 0x33);
            @memset(bytes[256..264], 0x44);
        } else {
            @memset(bytes[264..272], 0x33);
            @memset(bytes[96..104], 0x44);
            @memset(bytes[112..120], 0x55);
        }
        const after = try prefix.measure(io, source, native, bytes.len, .{});
        try std.testing.expectEqualSlices(u8, &before, &after);
        bytes[200] ^= 1;
        const changed = try prefix.measure(io, source, native, bytes.len, .{});
        try std.testing.expect(!std.mem.eql(u8, &before, &changed));
    }
}

test "N2-IMAGE-04 masks reject overlap header escape code coverage and integer overflow" {
    const bytes: [2048]u8 = @splat(0);
    const source: image.Source = .{ .bytes = &bytes };
    var native = layout(.pe);
    native.signature_command = native.pe_checksum;
    try std.testing.expectError(
        error.ImageInvalid,
        prefix.measure(io, source, native, bytes.len, .{}),
    );
    native = layout(.pe);
    native.pe_checksum = 512;
    try std.testing.expectError(
        error.ImageInvalid,
        prefix.measure(io, source, native, bytes.len, .{}),
    );
    native = layout(.pe);
    native.code = &.{.{ .offset = 64, .length = 4 }};
    try std.testing.expectError(
        error.ImageInvalid,
        prefix.measure(io, source, native, bytes.len, .{}),
    );
    native = layout(.macho);
    native.signature_command = std.math.maxInt(u64);
    try std.testing.expectError(
        error.ImageInvalid,
        prefix.measure(io, source, native, bytes.len, .{}),
    );
}

test "N2-IMAGE-04 format and CPU are part of the measurement domain" {
    const bytes: [2048]u8 = @splat(0);
    const source: image.Source = .{ .bytes = &bytes };
    var native = layout(.elf);
    const first = try prefix.measure(io, source, native, bytes.len, .{});
    native.cpu = .aarch64;
    const second = try prefix.measure(io, source, native, bytes.len, .{});
    try std.testing.expect(!std.mem.eql(u8, &first, &second));
    native = layout(.pe);
    const third = try prefix.measure(io, source, native, bytes.len, .{});
    try std.testing.expect(!std.mem.eql(u8, &first, &third));
}
