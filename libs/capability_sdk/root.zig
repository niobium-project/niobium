//! Capability guest ABI v1 for freestanding Wasm. Handles are scoped to one instance.
const std = @import("std");
pub const abi_version: u32 = 1;
pub const Kind = enum(u32) { input = 1, os = 2, arch = 3, previous_state = 4, asset = 5 };
pub const Error = error{ HostRefused, BufferTooLarge, InvalidHostResult };
const imported = struct {
    extern "niobium_v1" fn read(u32, u32, [*]u8, u32) i32;
    extern "niobium_v1" fn emit(u32, [*]const u8, u32) i32;
    extern "niobium_v1" fn state([*]const u8, u32) i32;
};

pub fn read(kind: Kind, handle: u32, buffer: []u8) Error![]const u8 {
    const length = std.math.cast(u32, buffer.len) orelse return error.BufferTooLarge;
    const result = imported.read(@backingInt(kind), handle, buffer.ptr, length);
    const written = std.math.cast(u32, result) orelse return error.HostRefused;
    if (written > buffer.len) return error.InvalidHostResult;
    return buffer[0..written];
}

pub fn emit(handle: u32, bytes: []const u8) Error!void {
    const length = std.math.cast(u32, bytes.len) orelse return error.BufferTooLarge;
    if (imported.emit(handle, bytes.ptr, length) != 0) return error.HostRefused;
}

pub fn state(bytes: []const u8) Error!void {
    const length = std.math.cast(u32, bytes.len) orelse return error.BufferTooLarge;
    if (imported.state(bytes.ptr, length) != 0) return error.HostRefused;
}
