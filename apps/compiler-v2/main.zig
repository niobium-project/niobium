//! Host compiler entrypoint for emitted product IR, exact locks and precompiled runtimes.

const std = @import("std");
const builtin = @import("builtin");
const compiler = @import("compiler");
const program = @import("program");
const contracts = @import("contracts");
const primitives = @import("host_primitives");
const options = @import("options.zig");
const integrations = @import("integrations.zig");
const storage = @import("workspace.zig");
const pipeline = compiler.pipeline;

pub fn main(init: std.process.Init) void {
    execute(init) catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn execute(init: std.process.Init) !void {
    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    const args = try options.parse(init.arena.allocator(), argv);
    if (args.action == .runtime_package) return @import("runtime_package.zig").run(init, args);
    try compile(init, args);
}

fn compile(init: std.process.Init, args: options.Options) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const model = try program.model.decode(arena, try read(arena, io, args.program.?));
    const lock = try compiler.lock.decode(arena, try read(arena, io, args.lock.?));
    const inputs = try arena.alloc(pipeline.Input, args.inputs.len);
    var files: std.ArrayList(std.Io.File) = .empty;
    defer for (files.items) |file| file.close(io);
    for (args.inputs, inputs) |argument, *input| {
        const file = try std.Io.Dir.cwd().openFile(io, argument.path, .{});
        files.append(arena, file) catch |err| {
            file.close(io);
            return err;
        };
        input.* = .{
            .id = argument.id,
            .source = try storage.source(io, file),
            .path = try std.Io.Dir.cwd().realPathFileAlloc(io, argument.path, arena),
        };
    }
    const runtime_package = try resolvePackage(arena, io, args, lock, inputs);
    const work = try storage.Workspace.init(arena, io, args.output);
    defer work.deinit();
    var context: integrations.Context = .{ .workspace = work.dir };
    const hosts = try arena.alloc(pipeline.HostInterface, primitives.interfaces.len);
    for (hosts, primitives.interfaces) |*host, primitive| host.* = .{
        .primitive = primitive.primitive,
        .interface = primitive.interface,
        .functions = primitive.functions,
    };
    const cache_dir = if (args.cache) |path| try openCache(io, path) else null;
    defer if (cache_dir) |dir| dir.close(io);
    const request: pipeline.Request = .{
        .product = model,
        .runtime_profile = runtime_package.profile,
        .inputs = inputs,
        .lock = lock,
        .runtime_id = args.runtime.?,
        .hosts = hosts,
        .locations = if (args.source_map) |path|
            (try pipeline.source_map.decode(arena, try read(arena, io, path))).locations
        else
            &.{},
        .inspector = .{
            .context = &context,
            .tool_id = args.worker,
            .inspect = integrations.inspect,
        },
        .compiler_version = try ownIdentity(arena, io),
        .cache = if (cache_dir) |dir| .{ .dir = dir, .io = io, .arena = arena } else null,
    };
    var diagnostic: ?pipeline.Diagnostic = null;
    const result = pipeline.build(arena, io, request, .{
        .dir = work.dir,
        .name = "ready",
        .finalizer = if (args.signer) |id| .{
            .tool_id = id,
            .finalize = integrations.finalize,
        } else null,
    }, &diagnostic) catch |err| {
        try report(arena, io, .{ .schema = 1, .status = "error", .diagnostic = diagnostic }, false);
        return err;
    };
    try work.publish("ready");
    try report(arena, io, .{ .schema = 1, .status = "ok", .result = result }, true);
}

fn resolvePackage(
    arena: std.mem.Allocator,
    io: std.Io,
    args: options.Options,
    lock: compiler.lock.Lock,
    inputs: []const pipeline.Input,
) !compiler.runtime_package.Package {
    const metadata = program.find(
        pipeline.Input,
        inputs,
        args.metadata.?,
    ) orelse return error.Usage;
    if (metadata.source.size() > contracts.limits.default.manifest_bytes) return error.InputLimit;
    const length = std.math.cast(usize, metadata.source.size()) orelse return error.InputLimit;
    const metadata_bytes = try arena.alloc(u8, length);
    var offset: usize = 0;
    while (offset < length) {
        const count = @min(64 << 10, length - offset);
        try metadata.source.read(io, offset, metadata_bytes[offset..][0..count]);
        offset += count;
    }
    return compiler.runtime_package.resolve(
        arena,
        lock,
        args.runtime.?,
        args.metadata.?,
        metadata_bytes,
    );
}

fn read(arena: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        arena,
        .limited(contracts.limits.default.program_bytes),
    );
}

fn openCache(io: std.Io, path: []const u8) !std.Io.Dir {
    try std.Io.Dir.cwd().createDirPath(io, path);
    return std.Io.Dir.cwd().openDir(io, path, .{});
}

fn ownIdentity(arena: std.mem.Allocator, io: std.Io) ![]const u8 {
    const path = if (builtin.target.os.tag == .linux)
        "/proc/self/exe"
    else
        try std.process.executablePathAlloc(io, arena);
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const digest = try storage.digest(io, try storage.source(io, file), null);
    return arena.dupe(u8, &contracts.ids.hexDigest(digest));
}

fn report(arena: std.mem.Allocator, io: std.Io, value: anytype, success: bool) !void {
    const bytes = try std.json.Stringify.valueAlloc(arena, value, .{});
    const output = if (success) std.Io.File.stdout() else std.Io.File.stderr();
    try output.writeStreamingAll(io, bytes);
    try output.writeStreamingAll(io, "\n");
}

test {
    _ = options;
}
