//! CLI values are typed input data. They never introduce runtime author expressions.
const std = @import("std");
const kernel = @import("kernel");
const program = @import("program");
const contracts = @import("contracts");
pub const Assignment = struct { id: []const u8, text: []const u8, encoded: bool };
pub const Arguments = struct {
    action: kernel.Action,
    roots: []const kernel.RootBinding,
    state_root: ?[]const u8,
    inputs: []const Assignment,
    failpoint: ?[]const u8,
};

pub fn parse(arena: std.mem.Allocator, argv: []const []const u8) !Arguments {
    if (argv.len < 4 or argv.len > 4 * contracts.limits.default.program_items + 8)
        return error.Usage;
    const action = std.meta.stringToEnum(kernel.Action, argv[1]) orelse return error.Usage;
    var roots: std.ArrayList(kernel.RootBinding) = .empty;
    var assignments: std.ArrayList(Assignment) = .empty;
    var state_root: ?[]const u8 = null;
    var failpoint: ?[]const u8 = null;
    var index: usize = 2;
    while (index < argv.len) : (index += 2) {
        if (index + 1 >= argv.len) return error.Usage;
        const flag = argv[index];
        const text = argv[index + 1];
        if (std.mem.eql(u8, flag, "--root")) {
            const entry = try assignment(text, false);
            if (roots.items.len >= contracts.limits.default.program_items) return error.Usage;
            try roots.append(arena, .{ .id = entry.id, .path = entry.text });
        } else if (std.mem.eql(u8, flag, "--set") or std.mem.eql(u8, flag, "--value")) {
            if (assignments.items.len >= contracts.limits.default.program_items) return error.Usage;
            try assignments.append(arena, try assignment(text, std.mem.eql(u8, flag, "--value")));
        } else if (std.mem.eql(u8, flag, "--state-root")) {
            if (state_root != null) return error.Usage;
            state_root = text;
        } else if (std.mem.eql(u8, flag, "--failpoint")) {
            if (failpoint != null) return error.Usage;
            failpoint = text;
        } else return error.Usage;
    }
    return .{
        .action = action,
        .roots = roots.items,
        .state_root = state_root,
        .inputs = assignments.items,
        .failpoint = failpoint,
    };
}

fn assignment(text: []const u8, encoded: bool) !Assignment {
    if (text.len > contracts.limits.default.program_bytes) return error.Usage;
    const equal = std.mem.indexOfScalar(u8, text, '=') orelse return error.Usage;
    const id = text[0..equal];
    try program.validation.identifier(id);
    return .{ .id = id, .text = text[equal + 1 ..], .encoded = encoded };
}

pub fn inputs(
    arena: std.mem.Allocator,
    args: Arguments,
    product: program.model.Product,
) ![]const kernel.Input {
    const result = try arena.alloc(kernel.Input, args.inputs.len);
    for (args.inputs, result) |input, *resolved| {
        const definition = program.find(program.model.Input, product.inputs, input.id) orelse
            return error.UnknownInput;
        const value = if (input.encoded)
            try contracts.json.decode(program.value.Value, arena, input.text, .{
                .max_bytes = contracts.limits.default.program_bytes,
                .limits = .{ .json_depth = program.model.wire_depth },
            })
        else
            try scalar(definition.default, input.text);
        try program.value.validate(value, .{});
        resolved.* = .{ .id = input.id, .value = value };
    }
    return result;
}

fn scalar(default: program.value.Value, text: []const u8) !program.value.Value {
    return switch (default) {
        .text => .{ .text = text },
        .enumeration => .{ .enumeration = text },
        .boolean => blk: {
            if (std.mem.eql(u8, text, "true")) break :blk .{ .boolean = true };
            if (std.mem.eql(u8, text, "false")) break :blk .{ .boolean = false };
            return error.Usage;
        },
        inline .uint8,
        .uint16,
        .uint32,
        .uint64,
        .sint8,
        .sint16,
        .sint32,
        .sint64,
        => |_, tag| blk: {
            const T = @FieldType(program.value.Value, @tagName(tag));
            const value = try std.fmt.parseInt(T, text, 10);
            break :blk @unionInit(program.value.Value, @tagName(tag), value);
        },
        inline .float32, .float64 => |_, tag| @unionInit(
            program.value.Value,
            @tagName(tag),
            try std.fmt.parseFloat(
                @FieldType(program.value.Value, @tagName(tag)),
                text,
            ),
        ),
        else => error.StructuredValueRequired,
    };
}

test "N2-RUNTIME-02: CLI preserves typed options and rejects ambiguous arguments" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const args = try parse(arena.allocator(), &.{
        "setup", "install", "--root", "tools=/tmp/tools", "--set", "enabled=false",
    });
    try std.testing.expectEqualStrings("tools", args.roots[0].id);
    try std.testing.expect(!(try scalar(.{ .boolean = true }, args.inputs[0].text)).boolean);
    try std.testing.expectError(error.Usage, scalar(.{ .boolean = true }, "maybe"));
    try std.testing.expectError(error.Usage, parse(arena.allocator(), &.{
        "setup", "install", "--root", "tools=/tmp/tools", "--state-root",
    }));
}
