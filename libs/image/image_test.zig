//! Descriptor boundaries are independent of native signing and execution qualification.

const std = @import("std");
const image = @import("root.zig");
const stream = @import("stream.zig");

const elf = image.fixture.elf;
const put = image.fixture.put;

test "N2-IMAGE-02 image references reject unknown versions and nonzero reserved bytes" {
    const value: image.Descriptor = .{
        .template_bytes = 4096,
        .prefix_bytes = 4096,
        .native_prefix_sha256 = @splat(4),
        .template_sha256 = @splat(1),
        .program = .{ .offset = 4096, .length = 16 },
        .program_sha256 = @splat(2),
        .payload = .{ .offset = 4112, .length = 2048 },
        .payload_sha256 = @splat(3),
    };
    var bytes = image.descriptor.encode(value);
    try std.testing.expectEqualDeep(value, try image.descriptor.decode(&bytes));
    bytes[255] = 1;
    try std.testing.expectError(error.ImageInvalid, image.descriptor.decode(&bytes));
    bytes[255] = 0;
    bytes[200] = 2;
    try std.testing.expectError(error.ImageUnsupported, image.descriptor.decode(&bytes));
    bytes[200] = 1;
    bytes[8] = 3;
    try std.testing.expectError(error.ImageUnsupported, image.descriptor.decode(&bytes));
    try image.descriptor.checkTemplate(&image.templateSlot());
    var old_template = image.templateSlot();
    @memset(old_template[200..204], 0);
    try std.testing.expectError(error.ImageInvalid, image.descriptor.checkTemplate(&old_template));
}

test "N2-IMAGE-02 image descriptor cannot overlap native data or wrap ranges" {
    const layout: image.native.Layout = .{
        .format = .elf,
        .cpu = .x86_64,
        .slot = .{ .offset = 1024, .length = 256 },
        .protected_end = 4096,
        .copy_length = 4096,
    };
    var value: image.Descriptor = .{
        .template_bytes = 4096,
        .prefix_bytes = 4096,
        .native_prefix_sha256 = @splat(4),
        .template_sha256 = @splat(1),
        .program = .{ .offset = 4096, .length = 16 },
        .program_sha256 = @splat(2),
        .payload = .{ .offset = 4112, .length = 2048 },
        .payload_sha256 = @splat(3),
    };
    try image.descriptor.ranges(value, layout, 6160);
    value.prefix_bytes = 1024;
    try std.testing.expectError(error.ImageInvalid, image.descriptor.ranges(value, layout, 6160));
    value.prefix_bytes = 4096;
    value.program.length = std.math.maxInt(u64);
    try std.testing.expectError(error.ImageInvalid, image.descriptor.ranges(value, layout, 6160));
}

test "N2-IMAGE-02 malformed native sections cannot overlap the descriptor" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bytes = elf();
    const layout = try image.native.inspect(
        arena.allocator(),
        std.testing.io,
        .{ .bytes = &bytes },
        .{},
    );
    try std.testing.expectEqual(@as(u64, 256), layout.slot.offset);
    put(u64, &bytes, 512 + 2 * 64 + 24, 128);
    try std.testing.expectError(error.ImageInvalid, image.native.inspect(
        arena.allocator(),
        std.testing.io,
        .{ .bytes = &bytes },
        .{},
    ));
    bytes = elf();
    put(u64, &bytes, 40, std.math.maxInt(u64));
    try std.testing.expectError(error.ImageInvalid, image.native.inspect(
        arena.allocator(),
        std.testing.io,
        .{ .bytes = &bytes },
        .{},
    ));
}

fn allocations(gpa: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const bytes = elf();
    const layout = try image.native.inspect(
        arena.allocator(),
        std.testing.io,
        .{ .bytes = &bytes },
        .{},
    );
    try std.testing.expectEqual(@as(usize, 1), layout.code.len);
}

test "N2-IMAGE-02 native parser allocation failures propagate" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocations, .{});
}

test "N2-IMAGE-02 captured template fingerprint survives later source mutation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const original = try tmp.dir.createFile(std.testing.io, "original", .{ .read = true });
    defer original.close(std.testing.io);
    const captured = try tmp.dir.createFile(std.testing.io, "captured", .{ .read = true });
    defer captured.close(std.testing.io);
    const bytes = elf();
    try original.writeStreamingAll(std.testing.io, &bytes);
    const digest = try stream.copy(std.testing.io, .{
        .source = .{ .file = .{ .handle = original, .length = bytes.len } },
        .length = bytes.len,
    }, captured, 0);
    try original.writePositionalAll(std.testing.io, "changed", 128);
    const frozen = try stream.hash(std.testing.io, .{
        .source = .{ .file = .{ .handle = captured, .length = bytes.len } },
        .length = bytes.len,
    });
    try std.testing.expectEqualSlices(u8, &digest, &frozen);
    try stream.move(std.testing.io, captured, .{ .offset = 0, .length = bytes.len }, 8);
    var moved: [1024]u8 = undefined; // SAFETY: positional read fills the compared snapshot.
    const count = try captured.readPositionalAll(std.testing.io, &moved, 8);
    try std.testing.expectEqual(bytes.len, count);
    try std.testing.expectEqualSlices(u8, &bytes, &moved);
}

test "N2-IMAGE-02 bounded native-image fuzz corpus" {
    const seed = elf();
    try std.testing.fuzz({}, fuzzImage, .{ .corpus = &.{ &seed, "MZ", "\xcf\xfa\xed\xfe" } });
}

fn fuzzImage(_: void, smith: *std.testing.Smith) !void {
    var bytes: [8192]u8 = @splat(0);
    const length = smith.slice(&bytes);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const value = image.native.inspect(arena.allocator(), std.testing.io, .{
        .bytes = bytes[0..length],
    }, .{});
    if (value) |layout| {
        try std.testing.expect(try layout.slot.end() <= length);
    } else |err| switch (err) {
        error.OutOfMemory => return err,
        else => return,
    }
}
