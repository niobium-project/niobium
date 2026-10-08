//! Capability Wasm envelope restrictions. WAMR performs instruction and type validation.

const std = @import("std");
const contracts = @import("contracts");

pub const Error = error{ WasmMalformed, WasmProfile, WasmLimitExceeded };
const magic = "\x00asm\x01\x00\x00\x00";

const Reader = struct {
    bytes: []const u8,
    offset: usize = 0,

    fn byte(r: *Reader) Error!u8 {
        if (r.offset >= r.bytes.len) return error.WasmMalformed;
        defer r.offset += 1;
        return r.bytes[r.offset];
    }

    fn integer(r: *Reader) Error!u32 {
        var value: u32 = 0;
        for (0..5) |index| {
            const b = try r.byte();
            if (index == 4 and b > 15) return error.WasmMalformed;
            const shift = std.math.cast(u5, index * 7) orelse return error.WasmMalformed;
            value |= @as(u32, b & 127) << shift;
            if (b & 128 == 0) return value;
        }
        return error.WasmMalformed;
    }

    fn slice(r: *Reader, length: u32) Error![]const u8 {
        if (length > r.bytes.len - r.offset) return error.WasmMalformed;
        const result = r.bytes[r.offset..][0..length];
        r.offset += length;
        return result;
    }

    fn name(r: *Reader) Error![]const u8 {
        return r.slice(try r.integer());
    }

    fn end(r: Reader) Error!void {
        if (r.offset != r.bytes.len) return error.WasmMalformed;
    }
};

const Profile = struct {
    limits: contracts.Limits,
    memory: bool = false,
    memory_export: bool = false,
    plan: bool = false,
    migration: bool = false,
    imports: u8 = 0,
    type_count: u32 = 0,
    function_count: u32 = 0,
    signatures: [contracts.limits.default.wasm_functions]u8 = @splat(255),
    function_types: [contracts.limits.default.wasm_functions]u32 = @splat(0),

    fn section(p: *Profile, id: u8, r: *Reader) Error!void {
        switch (id) {
            1 => try p.types(r),
            2 => try p.importsSection(r),
            3 => try p.functions(r),
            4 => try p.tables(r),
            5 => {
                if (try r.integer() != 1) return error.WasmProfile;
                try boundedLimits(r, p.limits.wasm_memory_pages);
                p.memory = true;
            },
            7 => try p.exports(r),
            8 => return error.WasmProfile,
            // These sections have no authority. The engine validates their complete bodies.
            0, 6, 9, 10, 11, 12 => r.offset = r.bytes.len,
            else => return error.WasmProfile,
        }
        try r.end();
    }

    fn types(p: *Profile, r: *Reader) Error!void {
        const count = try r.integer();
        if (count > p.limits.wasm_functions) return error.WasmLimitExceeded;
        p.type_count = count;
        for (0..count) |index| {
            if (try r.byte() != 0x60) return error.WasmProfile;
            const parameters = try values(r, p.limits.wasm_functions);
            const results = try values(r, 1);
            if (parameters.count <= 4 and parameters.all_i32 and
                results.count == 1 and results.all_i32)
                p.signatures[index] = std.math.cast(u8, parameters.count) orelse
                    return error.WasmMalformed;
        }
    }

    fn importsSection(p: *Profile, r: *Reader) Error!void {
        const count = try r.integer();
        if (count > 3) return error.WasmProfile;
        for (0..count) |_| {
            const module = try r.name();
            const name = try r.name();
            if (!std.mem.eql(u8, module, "niobium_v1")) return error.WasmProfile;
            const bit: u8 = if (std.mem.eql(u8, name, "read")) 1 else if (std.mem.eql(
                u8,
                name,
                "emit",
            )) 2 else if (std.mem.eql(u8, name, "state")) 4 else return error.WasmProfile;
            if (p.imports & bit != 0) return error.WasmProfile;
            p.imports |= bit;
            if (try r.byte() != 0) return error.WasmProfile;
            const type_index = try r.integer();
            if (type_index >= p.type_count) return error.WasmMalformed;
            const expected: u8 = switch (bit) {
                1 => 4,
                2 => 3,
                else => 2,
            };
            if (p.signatures[type_index] != expected) return error.WasmProfile;
            try p.appendFunction(type_index);
        }
    }

    fn functions(p: *Profile, r: *Reader) Error!void {
        const count = try r.integer();
        if (count > p.limits.wasm_functions) return error.WasmLimitExceeded;
        for (0..count) |_| {
            const type_index = try r.integer();
            if (type_index >= p.type_count) return error.WasmMalformed;
            try p.appendFunction(type_index);
        }
    }

    fn appendFunction(p: *Profile, type_index: u32) Error!void {
        if (p.function_count >= p.limits.wasm_functions) return error.WasmLimitExceeded;
        p.function_types[p.function_count] = type_index;
        p.function_count += 1;
    }

    fn exportSignature(p: *Profile, index: u32, parameter_count: u8) Error!void {
        if (index >= p.function_count) return error.WasmMalformed;
        if (p.signatures[p.function_types[index]] != parameter_count) return error.WasmProfile;
    }

    fn tables(p: *Profile, r: *Reader) Error!void {
        const count = try r.integer();
        if (count > 1) return error.WasmProfile;
        for (0..count) |_| {
            if (try r.byte() != 0x70) return error.WasmProfile;
            try boundedLimits(r, p.limits.wasm_table_elements);
        }
    }

    fn exports(p: *Profile, r: *Reader) Error!void {
        const count = try r.integer();
        if (count > 3) return error.WasmProfile;
        for (0..count) |_| {
            const name = try r.name();
            const kind = try r.byte();
            const index = try r.integer();
            if (std.mem.eql(u8, name, "memory")) {
                if (kind != 2 or index != 0 or p.memory_export) return error.WasmProfile;
                p.memory_export = true;
            } else if (std.mem.eql(u8, name, "nb_plan_v1")) {
                if (kind != 0 or p.plan) return error.WasmProfile;
                try p.exportSignature(index, 0);
                p.plan = true;
            } else if (std.mem.eql(u8, name, "nb_migrate_v1")) {
                if (kind != 0 or p.migration) return error.WasmProfile;
                try p.exportSignature(index, 2);
                p.migration = true;
            } else return error.WasmProfile;
        }
    }
};

const Values = struct { count: u32, all_i32: bool };

fn values(r: *Reader, maximum: u32) Error!Values {
    const count = try r.integer();
    if (count > maximum) return error.WasmLimitExceeded;
    var all_i32 = true;
    for (0..count) |_| switch (try r.byte()) {
        0x7f => {},
        0x7c...0x7e => all_i32 = false,
        else => return error.WasmProfile,
    };
    return .{ .count = count, .all_i32 = all_i32 };
}

fn boundedLimits(r: *Reader, maximum: u32) Error!void {
    // An explicit maximum is required; shared memory and memory64 are excluded.
    if (try r.byte() != 1) return error.WasmProfile;
    const minimum = try r.integer();
    const limit = try r.integer();
    if (minimum > limit or limit > maximum) return error.WasmLimitExceeded;
}

pub fn validate(bytes: []const u8, limits: contracts.Limits) Error!void {
    std.debug.assert(limits.wasm_module_bytes > 0);
    if (bytes.len > limits.wasm_module_bytes or
        limits.wasm_functions > contracts.limits.default.wasm_functions)
        return error.WasmLimitExceeded;
    if (!std.mem.startsWith(u8, bytes, magic)) return error.WasmMalformed;
    var r: Reader = .{ .bytes = bytes, .offset = magic.len };
    var profile: Profile = .{ .limits = limits };
    var seen: u16 = 0;
    var previous: u8 = 0;
    while (r.offset < bytes.len) {
        const id = try r.byte();
        if (id > 12) return error.WasmProfile;
        const length = try r.integer();
        var body: Reader = .{ .bytes = try r.slice(length) };
        if (id > 0) {
            const rank: u8 = if (id == 12) 10 else if (id >= 10) id + 1 else id;
            const bit = @as(u16, 1) << (std.math.cast(u4, id) orelse return error.WasmProfile);
            if (seen & bit != 0 or rank < previous) return error.WasmMalformed;
            seen |= bit;
            previous = rank;
        }
        try profile.section(id, &body);
    }
    if (!profile.memory or !profile.memory_export or !profile.plan) return error.WasmProfile;
}

test "N2-SAFE-01: Wasm profile rejects ambient imports, start and unbounded memory" {
    const wasi = magic ++ "\x02\x10\x01\x04wasi\x07fd_read\x00\x00";
    try std.testing.expectError(error.WasmProfile, validate(wasi, .{}));
    try std.testing.expectError(error.WasmProfile, validate(magic ++ "\x08\x01\x00", .{}));
    const memory = magic ++ "\x05\x03\x01\x00\x01";
    try std.testing.expectError(error.WasmProfile, validate(memory, .{}));
    try std.testing.expectError(error.WasmMalformed, validate(magic ++ "\x01\x80", .{}));
}

test "N2-SAFE-01: Wasm profile requires exports and enforces module budget" {
    try std.testing.expectError(error.WasmProfile, validate(magic, .{}));
    try std.testing.expectError(error.WasmLimitExceeded, validate(magic, .{
        .wasm_module_bytes = 4,
    }));
}

const minimal = magic ++
    "\x01\x05\x01\x60\x00\x01\x7f" ++
    "\x03\x02\x01\x00" ++
    "\x05\x04\x01\x01\x01\x01" ++
    "\x07\x17\x02\x06memory\x02\x00\x0anb_plan_v1\x00\x00" ++
    "\x0a\x06\x01\x04\x00\x41\x00\x0b";

test "N2-SAFE-01: capability signatures are checked before engine instantiation" {
    try validate(minimal, .{});
    var invalid = minimal.*;
    invalid[14] = 0x7e;
    try std.testing.expectError(error.WasmProfile, validate(&invalid, .{}));
    const wrong_import = magic ++ "\x01\x05\x01\x60\x00\x01\x7f" ++
        "\x02\x13\x01\x0aniobium_v1\x04read\x00\x00";
    try std.testing.expectError(error.WasmProfile, validate(wrong_import, .{}));
}

test "N2-SAFE-01: bounded profile parser tolerates every truncated or mutated fixture" {
    for (0..minimal.len) |length| {
        validate(minimal[0..length], .{}) catch |err| switch (err) {
            error.WasmMalformed, error.WasmProfile, error.WasmLimitExceeded => {},
        };
    }
    for (0..minimal.len) |offset| {
        var mutated = minimal.*;
        mutated[offset] = 0xff;
        validate(&mutated, .{}) catch |err| switch (err) {
            error.WasmMalformed, error.WasmProfile, error.WasmLimitExceeded => {},
        };
    }
}
