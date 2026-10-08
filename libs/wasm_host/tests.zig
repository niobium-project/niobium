//! N2 host conformance executes independently compiled guests through the real interpreter.
const std = @import("std");
const host = @import("wasm_host");
const fixtures = @import("fixtures");
const contracts = @import("contracts");

const context: host.Context = .{
    .inputs = &.{"sdk19"},
    .assets = &.{"verified payload"},
    .previous_state = "",
    .os = "macos",
    .arch = "arm64",
    .resource_count = 1,
};

test "N2-LIB-01: managed and independent libraries use the same host ABI" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const managed = try host.evaluate(a, fixtures.managed, context, null, .{});
    try std.testing.expectEqualStrings("verified payload", managed.resources[0].bytes);
    const zig_output = try host.evaluate(a, fixtures.zig_managed, context, null, .{});
    try std.testing.expectEqualStrings(managed.resources[0].bytes, zig_output.resources[0].bytes);
    const generated = try host.evaluate(a, fixtures.env_v1, context, null, .{});
    try std.testing.expectEqualStrings(
        "sdk=sdk19\nos=macos\narch=arm64\nprevious=\n",
        generated.resources[0].bytes,
    );
    try std.testing.expectEqualStrings("1:sdk19", generated.state);
    var changed = context;
    changed.inputs = &.{"sdk20"};
    const other = try host.evaluate(a, fixtures.env_v1, changed, null, .{});
    try std.testing.expect(std.mem.startsWith(u8, other.resources[0].bytes, "sdk=sdk20\n"));
}

test "N2-MIG-01: migration feeds the plan and rejects unsupported transitions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var old = context;
    old.previous_state = "1:sdk18";
    const output = try host.evaluate(a, fixtures.env_v2, old, .{ .from = 1, .to = 2 }, .{});
    try std.testing.expect(std.mem.endsWith(u8, output.resources[0].bytes, "previous=2:sdk18\n"));
    try std.testing.expectEqualStrings("2:sdk19", output.state);
    try std.testing.expectError(
        error.WasmRefused,
        host.evaluate(a, fixtures.env_v2, old, .{ .from = 2, .to = 3 }, .{}),
    );
    try std.testing.expectError(
        error.WasmABI,
        host.evaluate(a, fixtures.env_v1, old, .{ .from = 1, .to = 2 }, .{}),
    );
}

test "N2-SAFE-01: hostile guests fail without escaping their evaluation" {
    const errors = [_]host.Error{
        error.WasmTrap,
        error.WasmHandle,
        error.WasmTrap,
        error.WasmDuplicateOutput,
        error.WasmTrap,
        error.WasmLimitExceeded,
        error.WasmLimitExceeded,
        error.WasmRefused,
        error.WasmHandle,
    };
    inline for (errors, 0..) |expected, index| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(
            expected,
            host.evaluate(arena.allocator(), fixtures.bad[index], context, null, .{}),
        );
    }
}

test "N2-SAFE-01: instruction budget is shared by migration and planning" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const limits: contracts.Limits = .{ .wasm_instructions = 1600 };
    _ = try host.evaluate(a, fixtures.bad[9], context, null, limits);
    try std.testing.expectError(
        error.WasmTrap,
        host.evaluate(a, fixtures.bad[9], context, .{ .from = 1, .to = 2 }, limits),
    );
}

test "N2-SAFE-01: state, host call and output budgets are enforced" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(
        error.WasmLimitExceeded,
        host.evaluate(a, fixtures.managed, context, null, .{ .wasm_output_bytes = 2 }),
    );
    try std.testing.expectError(
        error.WasmLimitExceeded,
        host.evaluate(a, fixtures.env_v1, context, null, .{ .wasm_state_bytes = 2 }),
    );
    try std.testing.expectError(
        error.WasmLimitExceeded,
        host.evaluate(a, fixtures.managed, context, null, .{ .wasm_host_calls = 1 }),
    );
}

test "N2-SAFE-01: exact output and call limits accept valid work" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const payload = try allocator.alloc(u8, (contracts.Limits{}).wasm_output_bytes);
    @memset(payload, 'a');
    var maximum = context;
    maximum.assets = &.{payload};
    const output = try host.evaluate(allocator, fixtures.managed, maximum, null, .{
        .wasm_host_calls = 2,
    });
    try std.testing.expectEqualSlices(u8, payload, output.resources[0].bytes);
}

test "N2-SAFE-01: ambient imports and automatic initialization are rejected before loading" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(
        error.WasmProfile,
        host.evaluate(a, fixtures.bad[10], context, null, .{}),
    );
    try std.testing.expectError(
        error.WasmProfile,
        host.evaluate(a, fixtures.bad[11], context, null, .{}),
    );
}

test "N2-LIB-01: libraries control the desired subset of granted resource handles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var optional = context;
    optional.inputs = &.{"false"};
    const omitted = try host.evaluate(arena.allocator(), fixtures.optional, optional, null, .{});
    try std.testing.expectEqual(@as(usize, 0), omitted.resources.len);
    optional.inputs = &.{"true"};
    const enabled = try host.evaluate(arena.allocator(), fixtures.optional, optional, null, .{});
    try std.testing.expectEqualStrings("enabled", enabled.resources[0].bytes);
}

test "N2-MIG-01: proposed state writes preserve the phase's prior-state snapshot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var old = context;
    old.previous_state = "old";
    const result = try host.evaluate(arena.allocator(), fixtures.snapshot, old, null, .{});
    try std.testing.expectEqualStrings("old", result.resources[0].bytes);
    try std.testing.expectEqualStrings("new", result.state);
}
