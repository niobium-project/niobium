//! Adapt host values to the upstream C value API. Wasmtime owns Canonical ABI memory access.
const std = @import("std");
const program = @import("program");
const contracts = @import("contracts");
const c = @import("component_engine").c;
const Error = @import("root.zig").Error;
const Value = program.value.Value;
const Type = program.wit.Type;
const limits: contracts.Limits = .{};

pub fn toNative(arena: std.mem.Allocator, value: Value, ty: Type, depth: u8) Error!c.Val {
    if (depth >= limits.component_depth) return error.WorkerLimit;
    return switch (value) {
        .boolean => |v| .{ .kind = 0, .of = .{ .boolean = v } },
        .sint8 => |v| .{ .kind = 1, .of = .{ .s8 = v } },
        .uint8 => |v| .{ .kind = 2, .of = .{ .u8 = v } },
        .sint16 => |v| .{ .kind = 3, .of = .{ .s16 = v } },
        .uint16 => |v| .{ .kind = 4, .of = .{ .u16 = v } },
        .sint32 => |v| .{ .kind = 5, .of = .{ .s32 = v } },
        .uint32 => |v| .{ .kind = 6, .of = .{ .u32 = v } },
        .sint64 => |v| .{ .kind = 7, .of = .{ .s64 = v } },
        .uint64 => |v| .{ .kind = 8, .of = .{ .u64 = v } },
        .float32 => |v| .{ .kind = 9, .of = .{ .f32 = v } },
        .float64 => |v| .{ .kind = 10, .of = .{ .f64 = v } },
        .character => |v| .{ .kind = 11, .of = .{ .character = v } },
        .text => |v| .{ .kind = 12, .of = .{ .string = borrowed(v) } },
        .bytes => |v| blk: {
            if (v.len > limits.program_bytes) return error.WorkerLimit;
            const items = try arena.alloc(c.Val, v.len);
            for (items, v) |*item, byte| item.* = .{ .kind = 2, .of = .{ .u8 = byte } };
            break :blk .{
                .kind = 13,
                .of = .{ .list = .{ .size = items.len, .data = items.ptr } },
            };
        },
        .list, .tuple => |items| try toSequence(arena, items, ty, depth),
        .record => |fields| try toRecord(arena, fields, ty, depth),
        .variant => |v| .{ .kind = 16, .of = .{ .variant = .{
            .discriminant = borrowed(v.name),
            .val = try toPayload(arena, v.payload, try caseType(ty, v.name), depth + 1),
        } } },
        .enumeration => |v| .{ .kind = 17, .of = .{ .enumeration = borrowed(v) } },
        .option => |v| .{ .kind = 18, .of = .{
            .option = try toPayload(arena, v, ty.option, depth + 1),
        } },
        .result => |v| .{ .kind = 19, .of = .{ .result = .{
            .is_ok = v.success,
            .val = try toPayload(
                arena,
                v.payload,
                if (v.success) ty.result.ok else ty.result.err,
                depth + 1,
            ),
        } } },
        .flags => |names| blk: {
            const items = try arena.alloc(c.Bytes, names.len);
            for (items, names) |*item, name| item.* = borrowed(name);
            break :blk .{
                .kind = 20,
                .of = .{ .flags = .{ .size = items.len, .data = items.ptr } },
            };
        },
    };
}

fn toSequence(arena: std.mem.Allocator, values: []const Value, ty: Type, depth: u8) Error!c.Val {
    if (values.len > limits.component_types) return error.WorkerLimit;
    const items = try arena.alloc(c.Val, values.len);
    for (items, values, 0..) |*item, value, index| {
        const expected = if (ty == .list) ty.list.* else ty.tuple[index];
        item.* = try toNative(arena, value, expected, depth + 1);
    }
    const vector: c.Vec(c.Val) = .{ .size = items.len, .data = items.ptr };
    return if (ty == .list) .{ .kind = 13, .of = .{ .list = vector } } else .{
        .kind = 15,
        .of = .{ .tuple = vector },
    };
}

fn toRecord(
    arena: std.mem.Allocator,
    values: []const program.value.Field,
    ty: Type,
    depth: u8,
) Error!c.Val {
    const fields = try arena.alloc(c.Field, ty.record.len);
    for (fields, ty.record) |*field, expected| {
        const value = for (values) |input| {
            if (std.mem.eql(u8, input.name, expected.name)) break input.value;
        } else return error.WitTypeMismatch;
        field.* = .{
            .name = borrowed(expected.name),
            .val = try toNative(arena, value, expected.ty, depth + 1),
        };
    }
    return .{ .kind = 14, .of = .{ .record = .{ .size = fields.len, .data = fields.ptr } } };
}

fn toPayload(
    arena: std.mem.Allocator,
    value: ?*const Value,
    ty: ?*const Type,
    depth: u8,
) Error!?*c.Val {
    const input = value orelse return null;
    const item = try arena.create(c.Val);
    item.* = try toNative(arena, input.*, (ty orelse return error.WitTypeMismatch).*, depth);
    return item;
}

pub fn fromNative(arena: std.mem.Allocator, value: c.Val, ty: Type) Error!Value {
    var budget: Output = .{ .arena = arena };
    return budget.decode(value, ty, 0);
}

const Output = struct {
    arena: std.mem.Allocator,
    nodes: u32 = 0,
    bytes: usize = 0,

    fn decode(self: *Output, value: c.Val, ty: Type, depth: u8) Error!Value {
        if (depth >= limits.component_depth or self.nodes >= limits.component_types)
            return error.WorkerLimit;
        self.nodes += 1;
        return switch (value.kind) {
            0 => .{ .boolean = value.of.boolean },
            1 => .{ .sint8 = value.of.s8 },
            2 => .{ .uint8 = value.of.u8 },
            3 => .{ .sint16 = value.of.s16 },
            4 => .{ .uint16 = value.of.u16 },
            5 => .{ .sint32 = value.of.s32 },
            6 => .{ .uint32 = value.of.u32 },
            7 => .{ .sint64 = value.of.s64 },
            8 => .{ .uint64 = value.of.u64 },
            9 => .{ .float32 = value.of.f32 },
            10 => .{ .float64 = value.of.f64 },
            11 => .{ .character = value.of.character },
            12 => .{ .text = try self.text(value.of.string) },
            13, 15 => try self.sequence(value, ty, depth + 1),
            14 => try self.record(value.of.record, ty, depth + 1),
            16 => blk: {
                const name = try self.text(value.of.variant.discriminant);
                break :blk .{
                    .variant = .{
                        .name = name,
                        .payload = try self.payload(
                            value.of.variant.val,
                            try caseType(ty, name),
                            depth + 1,
                        ),
                    },
                };
            },
            17 => .{ .enumeration = try self.text(value.of.enumeration) },
            18 => .{ .option = try self.payload(value.of.option, ty.option, depth + 1) },
            19 => .{
                .result = .{
                    .success = value.of.result.is_ok,
                    .payload = try self.payload(
                        value.of.result.val,
                        if (value.of.result.is_ok) ty.result.ok else ty.result.err,
                        depth + 1,
                    ),
                },
            },
            20 => .{ .flags = try self.flags(value.of.flags) },
            21 => error.WorkerResource,
            else => error.WorkerUnsupported,
        };
    }

    fn sequence(self: *Output, value: c.Val, ty: Type, depth: u8) Error!Value {
        const vector = if (value.kind == 13) value.of.list else value.of.tuple;
        if (vector.size > limits.component_output_bytes) return error.WorkerLimit;
        const data = try elements(c.Val, vector);
        if (ty == .list and ty.list.* == .uint8) {
            try self.charge(data.len);
            const bytes = try self.arena.alloc(u8, data.len);
            for (data, bytes) |item, *byte| {
                if (item.kind != 2) return error.WitTypeMismatch;
                byte.* = item.of.u8;
            }
            return .{ .bytes = bytes };
        }
        if (data.len > limits.component_types) return error.WorkerLimit;
        const items = try self.arena.alloc(Value, data.len);
        for (data, items, 0..) |item, *result, index| {
            const expected = if (ty == .list) ty.list.* else ty.tuple[index];
            result.* = try self.decode(item, expected, depth);
        }
        return if (value.kind == 13) .{ .list = items } else .{ .tuple = items };
    }

    fn record(self: *Output, vector: c.Vec(c.Field), ty: Type, depth: u8) Error!Value {
        if (vector.size > limits.program_items or ty != .record or vector.size != ty.record.len)
            return error.WorkerLimit;
        const fields = try self.arena.alloc(program.value.Field, vector.size);
        for (try elements(c.Field, vector), fields) |field, *result| {
            const name = try self.text(field.name);
            const expected = try program.wit.selectType(ty, &.{name});
            result.* = .{ .name = name, .value = try self.decode(field.val, expected, depth) };
        }
        return .{ .record = fields };
    }

    fn flags(self: *Output, vector: c.Vec(c.Bytes)) Error![]const []const u8 {
        if (vector.size > limits.program_items) return error.WorkerLimit;
        const names = try self.arena.alloc([]const u8, vector.size);
        for (try elements(c.Bytes, vector), names) |name, *out| out.* = try self.text(name);
        return names;
    }

    fn payload(
        self: *Output,
        value: ?*const c.Val,
        ty: ?*const Type,
        depth: u8,
    ) Error!?*const Value {
        const native = value orelse return null;
        const result = try self.arena.create(Value);
        result.* = try self.decode(native.*, (ty orelse return error.WitTypeMismatch).*, depth);
        return result;
    }

    fn text(self: *Output, string: c.Bytes) Error![]const u8 {
        try self.charge(string.size);
        const bytes = try elements(u8, string);
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.ValueInvalid;
        return self.arena.dupe(u8, bytes);
    }

    fn charge(self: *Output, bytes: usize) Error!void {
        if (bytes > limits.component_output_bytes - self.bytes) return error.WorkerLimit;
        self.bytes += bytes;
    }
};

fn borrowed(value: []const u8) c.Bytes {
    return .{ .size = value.len, .data = @constCast(value.ptr) };
}

fn elements(comptime T: type, vector: c.Vec(T)) Error![]const T {
    if (vector.size == 0) return &.{};
    return (vector.data orelse return error.WorkerRequest)[0..vector.size];
}

fn caseType(ty: Type, name: []const u8) Error!?*const Type {
    if (ty != .variant or ty.variant.len > limits.component_types) return error.WitTypeMismatch;
    for (ty.variant) |case| {
        if (std.mem.eql(u8, case.name, name)) return case.payload;
    }
    return error.WitTypeMismatch;
}
