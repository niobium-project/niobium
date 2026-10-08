//! Evaluate a capability library without machine effects. Returned buffers belong to the arena.
const std = @import("std");
const contracts = @import("contracts");
const profile = @import("wasm_profile");
const wamr = @import("wamr");

pub const Context = struct {
    inputs: []const []const u8,
    assets: []const []const u8,
    previous_state: []const u8,
    os: []const u8,
    arch: []const u8,
    resource_count: u32,
};
pub const Migration = struct { from: u32, to: u32 };
pub const ResourceOutput = struct { handle: u32, bytes: []const u8 };
pub const Output = struct { resources: []const ResourceOutput, state: []const u8 };
pub const Error = profile.Error || error{
    OutOfMemory,
    WasmInitialization,
    WasmTrap,
    WasmRefused,
    WasmABI,
    WasmHandle,
    WasmDuplicateOutput,
    WasmMissingOutput,
};

const Evaluation = struct {
    arena: std.mem.Allocator,
    context: Context,
    limits: contracts.Limits,
    resources: std.ArrayList(ResourceOutput) = .empty,
    state: []const u8,
    read_state: []const u8,
    seen: []bool,
    migrating: bool = false,
    state_written: bool = false,
    calls: u32 = 0,
    bytes_written: u32 = 0,
    fault: ?Error = null,

    fn call(e: *Evaluation) Error!void {
        if (e.calls >= e.limits.wasm_host_calls) return error.WasmLimitExceeded;
        e.calls += 1;
    }

    fn read(e: *Evaluation, kind: u32, index: u32, target: []u8) Error!i32 {
        try e.call();
        const bytes = switch (kind) {
            1 => input: {
                if (index >= e.context.inputs.len) return error.WasmHandle;
                break :input e.context.inputs[index];
            },
            5 => asset: {
                if (index >= e.context.assets.len) return error.WasmHandle;
                break :asset e.context.assets[index];
            },
            2, 3, 4 => bytes: {
                if (index != 0) return error.WasmHandle;
                break :bytes switch (kind) {
                    2 => e.context.os,
                    3 => e.context.arch,
                    else => e.read_state,
                };
            },
            else => return error.WasmHandle,
        };
        if (bytes.len > target.len) return error.WasmLimitExceeded;
        const count = std.math.cast(i32, bytes.len) orelse return error.WasmLimitExceeded;
        @memcpy(target[0..bytes.len], bytes);
        return count;
    }

    fn write(e: *Evaluation, handle: u32, bytes: []const u8) Error!void {
        try e.call();
        const count = std.math.cast(u32, bytes.len) orelse return error.WasmLimitExceeded;
        if (count > e.limits.wasm_output_bytes - e.bytes_written)
            return error.WasmLimitExceeded;
        e.bytes_written += count;
        if (handle == std.math.maxInt(u32)) {
            if (count > e.limits.wasm_state_bytes) return error.WasmLimitExceeded;
            if (e.state_written) return error.WasmDuplicateOutput;
            e.state = try e.arena.dupe(u8, bytes);
            e.state_written = true;
        } else {
            if (e.migrating or handle >= e.seen.len) return error.WasmHandle;
            if (e.seen[handle]) return error.WasmDuplicateOutput;
            e.seen[handle] = true;
            try e.resources.append(e.arena, .{
                .handle = handle,
                .bytes = try e.arena.dupe(u8, bytes),
            });
        }
    }
};

fn callbackRead(
    context_ptr: *anyopaque,
    kind: u32,
    index: u32,
    bytes: [*]u8,
    len: u32,
) callconv(.c) i32 {
    const e: *Evaluation = @ptrCast(@alignCast(context_ptr));
    return e.read(kind, index, bytes[0..len]) catch |err| {
        e.fault = err;
        return -1;
    };
}

fn callbackWrite(
    context_ptr: *anyopaque,
    handle: u32,
    bytes: [*]const u8,
    len: u32,
) callconv(.c) i32 {
    const e: *Evaluation = @ptrCast(@alignCast(context_ptr));
    e.write(handle, bytes[0..len]) catch |err| {
        e.fault = err;
        return -1;
    };
    return 0;
}

fn callbackPhase(context_ptr: *anyopaque, phase: u32) callconv(.c) void {
    const e: *Evaluation = @ptrCast(@alignCast(context_ptr));
    if (e.migrating and !e.state_written) e.fault = error.WasmMissingOutput;
    e.read_state = e.state;
    e.migrating = phase == 1;
    e.state_written = false;
}

pub fn evaluate(
    arena: std.mem.Allocator,
    wasm: []const u8,
    context: Context,
    migration: ?Migration,
    limits: contracts.Limits,
) Error!Output {
    std.debug.assert(limits.wasm_output_bytes > 0);
    try profile.validate(wasm, limits);
    try validateContext(context, limits);
    const instructions = std.math.cast(i32, limits.wasm_instructions) orelse
        return error.WasmLimitExceeded;
    if (instructions <= 0) return error.WasmLimitExceeded;
    const heap = try arena.alignedAlloc(u8, .@"8", limits.wasm_heap_bytes);
    defer arena.free(heap);
    const bytes = try arena.dupe(u8, wasm);
    defer arena.free(bytes);
    var ev: Evaluation = .{
        .arena = arena,
        .context = context,
        .limits = limits,
        .state = try arena.dupe(u8, context.previous_state),
        .read_state = context.previous_state,
        .seen = try arena.alloc(bool, context.resource_count),
    };
    @memset(ev.seen, false);
    const request: wamr.Request = .{
        .context = &ev,
        .read = callbackRead,
        .write = callbackWrite,
        .phase = callbackPhase,
        .heap = heap.ptr,
        .heap_size = limits.wasm_heap_bytes,
        .stack_size = limits.wasm_stack_bytes,
        .instructions = instructions,
        .migrate = @intFromBool(migration != null),
        .from = if (migration) |m| m.from else 0,
        .to = if (migration) |m| m.to else 0,
    };
    const result = wamr.nb_wamr_evaluate(bytes.ptr, std.math.cast(u32, bytes.len) orelse
        return error.WasmLimitExceeded, &request);
    if (ev.fault) |err| return err;
    switch (result) {
        0 => {},
        1 => return error.WasmInitialization,
        2 => return error.WasmMalformed,
        3 => return error.WasmTrap,
        4 => return error.WasmRefused,
        else => return error.WasmABI,
    }
    return .{ .resources = try ev.resources.toOwnedSlice(arena), .state = ev.state };
}

fn validateContext(context: Context, limits: contracts.Limits) Error!void {
    if (context.inputs.len > limits.program_items or context.assets.len > limits.program_items or
        context.resource_count > limits.program_items) return error.WasmLimitExceeded;
    if (context.previous_state.len > limits.wasm_state_bytes) return error.WasmLimitExceeded;
    if (context.os.len > limits.json_string_bytes or context.arch.len > limits.json_string_bytes)
        return error.WasmLimitExceeded;
    for (context.inputs) |input| {
        if (input.len > limits.json_string_bytes) return error.WasmLimitExceeded;
    }
    for (context.assets) |asset| {
        if (asset.len > limits.program_blob_bytes) return error.WasmLimitExceeded;
    }
}
