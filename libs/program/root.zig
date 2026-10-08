//! Compiled product model shared by the compiler and runtime. Author programs construct typed
//! values; this module owns normalization and strict machine-protocol decoding.

const std = @import("std");
const contracts = @import("contracts");

pub const validation = @import("validate.zig");
pub const image = @import("image.zig");
pub const profile = @import("profile.zig");
pub const value = @import("value.zig");
pub const model = @import("model.zig");
pub const wit = @import("wit.zig");
pub const worker = @import("worker.zig");
pub const Error = contracts.json.DecodeError || error{
    ProgramInvalid,
    ProgramLimit,
    ProgramDuplicate,
    ProgramReference,
    ProgramDigest,
    ProgramPath,
    ProgramUnsupported,
};

pub const Input = struct { id: []const u8, default: []const u8 };
pub const Library = struct {
    id: []const u8,
    abi: u32 = 1,
    sha256: []const u8,
    wasm_hex: []const u8,
};
pub const Asset = struct { id: []const u8, sha256: []const u8, data_hex: []const u8 };
pub const Resource = struct { id: []const u8, path: []const u8 };
pub const Migration = struct { id: []const u8, from: u32, to: u32 };
pub const Instance = struct {
    id: []const u8,
    library: []const u8,
    inputs: []const []const u8 = &.{},
    assets: []const []const u8 = &.{},
    resources: []const []const u8 = &.{},
    state_version: u32 = 1,
    migrations: []const Migration = &.{},
};
pub const Program = struct {
    schema: u32 = 1,
    runtime_abi: u32 = 1,
    product_id: []const u8,
    release_sequence: u64,
    model_version: u32 = 1,
    inputs: []const Input = &.{},
    libraries: []const Library = &.{},
    assets: []const Asset = &.{},
    resources: []const Resource = &.{},
    instances: []const Instance = &.{},
    upgrades: []const Migration = &.{},
};

pub fn validate(product: Program) Error!void {
    return validation.program(product, .{});
}

pub fn decode(arena: std.mem.Allocator, bytes: []const u8) Error!Program {
    const limits: contracts.Limits = .{};
    const product = try contracts.json.decode(Program, arena, bytes, .{
        .max_bytes = limits.program_bytes,
        .max_schema = 1,
        .limits = .{ .json_string_bytes = limits.program_blob_bytes * 2 },
    });
    try validate(product);
    return product;
}

pub fn encode(arena: std.mem.Allocator, product: Program) Error![]const u8 {
    const normalized = try normalize(arena, product);
    const bytes = try std.json.Stringify.valueAlloc(arena, normalized, .{});
    if (bytes.len > (contracts.Limits{}).program_bytes) return error.ProgramLimit;
    return bytes;
}

pub fn normalize(arena: std.mem.Allocator, product: Program) Error!Program {
    try validate(product);
    var result = product;
    result.inputs = try sorted(Input, arena, product.inputs);
    result.libraries = try sorted(Library, arena, product.libraries);
    result.assets = try sorted(Asset, arena, product.assets);
    result.resources = try sorted(Resource, arena, product.resources);
    const instances = try sorted(Instance, arena, product.instances);
    for (instances) |*instance| {
        instance.migrations = try sorted(Migration, arena, instance.migrations);
    }
    result.instances = instances;
    result.upgrades = try sorted(Migration, arena, product.upgrades);
    return result;
}

fn sorted(comptime T: type, arena: std.mem.Allocator, source: []const T) Error![]T {
    const items = try arena.dupe(T, source);
    std.mem.sort(T, items, {}, struct {
        fn less(_: void, a: T, b: T) bool {
            return std.mem.lessThan(u8, a.id, b.id);
        }
    }.less);
    return items;
}

pub fn digest(arena: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    var hash: [32]u8 = undefined; // SAFETY: hash writes every byte.
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    return encodeHex(arena, &hash);
}

pub fn encodeHex(arena: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    if (bytes.len > (contracts.Limits{}).program_blob_bytes) return error.ProgramLimit;
    const output = try arena.alloc(u8, bytes.len * 2);
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |byte, i| {
        output[2 * i] = alphabet[byte >> 4];
        output[2 * i + 1] = alphabet[byte & 15];
    }
    return output;
}

pub fn decodeHex(arena: std.mem.Allocator, text: []const u8) Error![]u8 {
    if (text.len > (contracts.Limits{}).program_blob_bytes * 2) return error.ProgramLimit;
    if (text.len % 2 != 0) return error.ProgramInvalid;
    const output = try arena.alloc(u8, text.len / 2);
    for (output, 0..) |*byte, i| {
        byte.* = (try nibble(text[2 * i])) * 16 + try nibble(text[2 * i + 1]);
    }
    return output;
}

pub fn nibble(byte: u8) Error!u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        else => error.ProgramInvalid,
    };
}

pub fn find(comptime T: type, items: []const T, id: []const u8) ?T {
    for (items) |item| {
        if (std.mem.eql(u8, item.id, id)) return item;
    }
    return null;
}

test {
    _ = model;
    _ = profile;
    _ = value;
    _ = validation;
    _ = image;
    _ = @import("program_test.zig");
}
