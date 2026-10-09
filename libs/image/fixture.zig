//! Synthetic ELF template for parser and compiler tests, not native execution evidence.

const std = @import("std");
const image = @import("root.zig");

pub fn elf() [1024]u8 {
    var bytes: [1024]u8 = @splat(0);
    @memcpy(bytes[0..7], "\x7fELF\x02\x01\x01");
    put(u16, &bytes, 16, 2);
    put(u16, &bytes, 18, 62);
    put(u64, &bytes, 32, 64);
    put(u64, &bytes, 40, 512);
    put(u16, &bytes, 52, 64);
    put(u16, &bytes, 54, 56);
    put(u16, &bytes, 56, 1);
    put(u16, &bytes, 58, 64);
    put(u16, &bytes, 60, 4);
    put(u16, &bytes, 62, 3);
    put(u32, &bytes, 64, 1);
    put(u32, &bytes, 68, 5);
    put(u64, &bytes, 96, 768);
    bytes[128] = 0xc3;
    const strings = "\x00.text\x00.nbprod\x00.shstrtab\x00";
    @memcpy(bytes[160..][0..strings.len], strings);
    @memcpy(bytes[256..512], &image.templateSlot());
    const offsets = [_]u64{ 128, 256, 160 };
    const lengths = [_]u64{ 1, 256, strings.len };
    for ([_]u32{ 1, 7, 15 }, offsets, lengths, 1..) |name, offset, length, index| {
        const header = 512 + index * 64;
        put(u32, &bytes, header, name);
        put(u32, &bytes, header + 4, if (index == 3) 3 else 1);
        put(u64, &bytes, header + 8, if (index == 1) 6 else if (index == 2) 3 else 0);
        put(u64, &bytes, header + 24, offset);
        put(u64, &bytes, header + 32, length);
    }
    return bytes;
}

pub fn put(comptime T: type, bytes: []u8, at: usize, value: T) void {
    std.mem.writeInt(T, bytes[at..][0..@sizeOf(T)], value, .little);
}
