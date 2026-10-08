//! Disposable standard-ABI worker. The caller owns process lifetime and its wall-clock deadline.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const engine = @import("component_engine");
const convert = @import("values.zig");
const inspect = @import("inspect.zig");
pub const protocol = @import("protocol.zig");
pub const Error = contracts.json.DecodeError || program.wit.Error || engine.Error || error{
    WorkerRead,
    WorkerWrite,
    WorkerRequest,
    WorkerDigest,
    WorkerOutput,
    WorkerResource,
    WorkerUnsupported,
    WorkerLimit,
};
const limits: contracts.Limits = .{};

pub fn serve(arena: std.mem.Allocator, io: std.Io) Error!void {
    // SAFETY: Reader writes the initialized prefix before it is observed.
    var buffer: [4096]u8 = undefined;
    var reader = std.Io.File.stdin().reader(io, &buffer);
    const input = reader.interface.allocRemaining(
        arena,
        .limited64(@as(u64, limits.program_bytes) + 1),
    ) catch return error.WorkerRead;
    const response = execute(arena, io, input) catch |err| failure(@errorName(err));
    const storage = try arena.alloc(u8, limits.component_output_bytes);
    var writer: std.Io.Writer = .fixed(storage);
    encode(response, &writer) catch {
        writer = .fixed(storage);
        encode(failure("WorkerOutput"), &writer) catch return error.WorkerOutput;
    };
    std.Io.File.stdout().writeStreamingAll(io, writer.buffered()) catch return error.WorkerWrite;
}

pub fn execute(arena: std.mem.Allocator, io: std.Io, input: []const u8) Error!protocol.Response {
    const request = try contracts.json.decode(protocol.Request, arena, input, .{
        .max_bytes = limits.program_bytes,
        .max_schema = 1,
        .limits = .{ .json_depth = program.model.wire_depth },
    });
    if (request.schema != 1 or request.args.len > limits.program_items) return error.WorkerRequest;
    if (request.allowed_imports.len > limits.program_items) return error.WorkerLimit;
    const bytes = try readSource(arena, io, request.source);
    var session = try engine.Session.load(bytes, engineLimits());
    defer session.deinit();
    const description = try inspect.describe(arena, &session);
    if (request.action == .inspect) return .{ .status = .ok, .inspection = description };
    if (request.allowed_imports.len != 0) return error.WorkerUnsupported;
    const function = try program.wit.findFunction(
        description.exports,
        request.interface,
        request.function,
    );
    if (function.asynchronous) return error.WorkerUnsupported;
    if (request.args.len != function.params.len) return error.WitTypeMismatch;
    const arguments = try arena.alloc(engine.c.Val, request.args.len);
    for (request.args, function.params, arguments) |value, parameter, *argument| {
        try program.wit.validateValue(value, parameter.ty);
        argument.* = try convert.toNative(arena, value, parameter.ty, 0);
    }
    const type_imports = try arena.alloc([]const u8, description.imports.len);
    for (description.imports, type_imports) |item, *name| {
        if (!try program.wit.isTypeOnlyImport(item)) return error.UnauthorizedImport;
        name.* = item.name;
    }
    try session.instantiate(type_imports);
    // SAFETY: Session.call initializes output slots before invoking the C API.
    var result: [1]engine.c.Val = undefined;
    const count: usize = if (function.result != null) 1 else 0;
    try session.call(
        .{ .interface = request.interface, .function = request.function },
        arguments,
        result[0..count],
    );
    if (count == 0) return .{ .status = .ok };
    defer engine.c.wasmtime_component_val_delete(&result[0]);
    const value = try convert.fromNative(arena, result[0], function.result.?.*);
    try program.wit.validateValue(value, function.result.?.*);
    return .{ .status = .ok, .result = value };
}

fn readSource(arena: std.mem.Allocator, io: std.Io, source: protocol.Source) Error![]const u8 {
    const spec: protocol.RangeSource = switch (source) {
        .file => |file| .{
            .path = file.path,
            .length = file.length,
            .sha256 = file.sha256,
            .offset = 0,
        },
        .range => |range| range,
    };
    if (spec.length > limits.component_bytes or spec.path.len > limits.path_bytes)
        return error.WorkerLimit;
    if (spec.sha256.len != 64) return error.WorkerDigest;
    const file = std.Io.Dir.cwd().openFile(
        io,
        spec.path,
        .{ .follow_symlinks = false },
    ) catch return error.WorkerRead;
    defer file.close(io);
    const stat = file.stat(io) catch return error.WorkerRead;
    if (stat.kind != .file) return error.WorkerRead;
    const end = std.math.add(u64, spec.offset, spec.length) catch return error.WorkerLimit;
    if (end > stat.size or (source == .file and stat.size != end)) return error.WorkerRead;
    const bytes = try arena.alloc(u8, spec.length);
    const count = file.readPositionalAll(io, bytes, spec.offset) catch return error.WorkerRead;
    if (count != bytes.len) return error.WorkerRead;
    // SAFETY: Sha256.hash fills the complete digest.
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    if (!std.mem.eql(u8, &std.fmt.bytesToHex(hash, .lower), spec.sha256))
        return error.WorkerDigest;
    return bytes;
}

fn engineLimits() engine.Limits {
    return .{
        .component_bytes = limits.component_bytes,
        .modules = limits.component_modules,
        .types = limits.component_types,
        .depth = limits.component_depth,
        .memory_bytes = limits.component_memory_bytes,
        .memories = limits.component_memories,
        .table_elements = limits.component_table_elements,
        .instructions = limits.wasm_instructions,
        .stack_bytes = limits.component_stack_bytes,
        .allocation_bytes = limits.component_allocation_bytes,
    };
}

fn encode(response: protocol.Response, writer: *std.Io.Writer) error{WriteFailed}!void {
    try std.json.Stringify.value(response, .{}, writer);
    try writer.writeByte('\n');
}

fn failure(code: []const u8) protocol.Response {
    return .{ .status = .@"error", .@"error" = .{ .code = code, .message = code } };
}
