//! Complete published runtime. Compiler assembly inserts data without relinking this executable.
const std = @import("std");
const builtin = @import("builtin");
const image = @import("image");
const kernel = @import("kernel");
const platform = @import("platform");
const component_worker = @import("component_worker");
const primitives = @import("host_primitives");
const product = @import("product.zig");
const arguments = @import("arguments.zig");
const section = if (builtin.os.tag == .macos) "__DATA,__nbproduct" else ".nbprod";
pub export var niobium_product_slot: [image.descriptor.size]u8 linksection(section) =
    image.templateSlot();

pub fn main(init: std.process.Init) void {
    execute(init) catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn execute(init: std.process.Init) !void {
    std.mem.doNotOptimizeAway(&niobium_product_slot);
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);
    if (argv.len == 2 and std.mem.eql(u8, argv[1], "--component-worker")) {
        return component_worker.serve(arena, init.io);
    }
    if (argv.len == 2 and std.mem.eql(u8, argv[1], "profile")) {
        return output(arena, init.io, primitives.runtimeProfile(try primitives.currentTarget()));
    }
    const args = try arguments.parse(arena, argv);
    const executable = try std.process.executablePathAlloc(init.io, arena);
    const loaded_slot: *volatile [image.descriptor.size]u8 = &niobium_product_slot;
    const expected = loaded_slot.*;
    var packaged: ?product.Product = if (args.action.needsProduct())
        try product.Product.open(arena, init.io, executable, try temporary(init), &expected)
    else
        null;
    defer if (packaged) |value| value.deinit(init.io);
    var host = platform.Host.init(init.io, .{ .env = .{} });
    var fault: Fault = .{ .io = init.io, .expected = args.failpoint };
    const model = if (packaged) |value| value.model else null;
    const state_root = args.state_root orelse state: {
        if (model) |value| break :state value.state_root;
        if (args.roots.len == 1) break :state args.roots[0].id;
        return error.StateRootRequired;
    };
    if (model == null and args.inputs.len != 0) return error.Usage;
    const result = kernel.run(.{
        .io = init.io,
        .arena = arena,
        .model = model,
        .action = args.action,
        .roots = args.roots,
        .state_root = state_root,
        .inputs = if (model) |value| try arguments.inputs(arena, args, value) else &.{},
        .evaluator = if (packaged) |*value| value.evaluator.evaluation() else .{},
        .content = if (packaged) |*value| value.evaluator.provider() else .{},
        .platform = host.platform(),
        .checkpoint = .{ .context = &fault, .call = Fault.checkpoint },
    }) catch |err| {
        if (packaged) |value| if (value.evaluator.diagnostic) |diagnostic| {
            try output(arena, init.io, .{ .status = "error", .diagnostic = diagnostic });
        };
        return err;
    };
    try output(arena, init.io, result);
}

fn output(arena: std.mem.Allocator, io: std.Io, value: anytype) !void {
    const bytes = try std.json.Stringify.valueAlloc(arena, value, .{});
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
    try std.Io.File.stdout().writeStreamingAll(io, "\n");
}

const Fault = struct {
    io: std.Io,
    expected: ?[]const u8,

    fn checkpoint(opaque_context: ?*anyopaque, name: []const u8, root: ?[]const u8) void {
        const self: *Fault = @ptrCast(@alignCast(opaque_context orelse return));
        const expected = self.expected orelse return;
        var buffer: [256]u8 = undefined; // SAFETY: bufPrint initializes the compared slice.
        const qualified = if (root) |id| std.fmt.bufPrint(&buffer, "{s}:{s}", .{ name, id }) catch
            std.process.exit(2) else name;
        if (!std.mem.eql(u8, expected, qualified)) return;
        std.Io.File.stderr().writeStreamingAll(self.io, "NIOBIUM_FAILPOINT\n") catch
            std.process.exit(2);
        // The acceptance parent kills this process; a missing parent never resumes mutation.
        for (0..300) |_| std.Io.sleep(self.io, .fromMilliseconds(100), .awake) catch
            std.process.exit(2);
        std.process.exit(2);
    }
};

test {
    _ = arguments;
}

fn temporary(init: std.process.Init) ![]const u8 {
    return if (builtin.os.tag == .windows)
        init.environ_map.get("TEMP") orelse init.environ_map.get("TMP") orelse
            error.TemporaryDirectoryMissing
    else
        init.environ_map.get("TMPDIR") orelse "/tmp";
}
