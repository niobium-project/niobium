//! External host tools use captured locked binaries, never mutable caller paths.

const std = @import("std");
const compiler = @import("compiler");
const client = @import("component_client");
const program = @import("program");
const image = @import("image");
const pipeline = compiler.pipeline;

pub const Context = struct { workspace: std.Io.Dir };

pub fn inspect(
    opaque_context: ?*anyopaque,
    arena: std.mem.Allocator,
    io: std.Io,
    library: program.model.Library,
    input: pipeline.Input,
    tool: ?pipeline.Input,
) pipeline.IntegrationError!program.wit.Inspection {
    const pointer = opaque_context orelse return error.ContractUnavailable;
    const context: *Context = @ptrCast(@alignCast(pointer));
    const executable = (tool orelse return error.ContractUnavailable).path orelse
        return error.ContractUnavailable;
    const worker: client.Client = .{ .executable = executable, .workspace = context.workspace };
    const length = std.math.cast(u32, input.source.size()) orelse return error.ContractRejected;
    const path = input.path orelse return error.ContractUnavailable;
    const offset = if (input.source == .file) input.source.file.offset else 0;
    const response = worker.call(arena, io, .{
        .action = .inspect,
        .source = .{
            .range = .{
                .path = path,
                .offset = offset,
                .length = length,
                .sha256 = library.sha256,
            },
        },
    }) catch |err| return map(err);
    if (response.status != .ok) return error.ContractRejected;
    return response.inspection orelse error.ContractRejected;
}

pub fn finalize(
    _: ?*anyopaque,
    arena: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    format: image.Format,
    tool: ?pipeline.Input,
) pipeline.IntegrationError!void {
    if (format != .macho) return error.ContractRejected;
    const executable = (tool orelse return error.ContractUnavailable).path orelse
        return error.ContractUnavailable;
    try command(arena, io, &.{ executable, "sign", path });
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return error.ContractUnavailable;
    defer file.close(io);
    const size = (file.stat(io) catch return error.ContractUnavailable).size;
    image.verifyAdhoc(arena, io, .{ .file = .{ .handle = file, .length = size } }, .{}) catch
        return error.ContractRejected;
}

fn command(
    arena: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
) pipeline.IntegrationError!void {
    const result = std.process.run(arena, io, .{
        .argv = argv,
        .stdout_limit = .limited(64 << 10),
        .stderr_limit = .limited(64 << 10),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(60), .clock = .awake } },
    }) catch |err| return map(err);
    if (!result.term.success()) return error.ContractRejected;
}

fn map(err: anyerror) pipeline.IntegrationError {
    std.log.err("compiler tool failure: {s}", .{@errorName(err)});
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.Canceled => error.Canceled,
        else => error.ContractUnavailable,
    };
}
