//! Headless precompiled runtime profile. Product bytes are inserted into the reserved section
//! after this executable is built; startup reads them from its executable file.

const std = @import("std");
const program = @import("program");
const runtime = @import("runtime");

const slot_size = program.image.capacity;
pub export var niobium_product_slot: [slot_size]u8 linksection("__DATA,__nbproduct") = slot();

fn slot() [program.image.capacity]u8 {
    var bytes: [program.image.capacity]u8 = @splat(0);
    @memcpy(bytes[0..8], program.image.runtime_magic);
    std.mem.writeInt(u32, bytes[8..12], 1, .little);
    std.mem.writeInt(u32, bytes[12..16], program.image.capacity, .little);
    return bytes;
}

pub fn main(init: std.process.Init) !void {
    execute(init) catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        std.process.exit(1);
    };
}

const Arguments = struct {
    action: runtime.Action,
    root: []const u8,
    inputs: []const runtime.state.Value,
    failpoint: ?[]const u8,
};

fn execute(init: std.process.Init) !void {
    std.mem.doNotOptimizeAway(&niobium_product_slot);
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);
    if (argv.len == 2 and std.mem.eql(u8, argv[1], "version")) {
        try std.Io.File.stdout().writeStreamingAll(
            init.io,
            "niobium-runtime abi=1 macos-aarch64\n",
        );
        return;
    }
    const args = try arguments(arena, argv);
    const needs_product = args.action == .install or args.action == .apply;
    const model = if (needs_product) try ownProgram(init) else null;
    var fault: Fault = .{ .io = init.io, .name = args.failpoint };
    const result = try runtime.run(.{
        .io = init.io,
        .arena = arena,
        .root = args.root,
        .action = args.action,
        .model = model,
        .inputs = args.inputs,
        .checkpoint = .{ .context = &fault, .call = Fault.checkpoint },
    });
    const bytes = try std.json.Stringify.valueAlloc(arena, result, .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, bytes);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}

fn ownProgram(init: std.process.Init) !program.Program {
    const arena = init.arena.allocator();
    const path = try std.process.executablePathAlloc(init.io, arena);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, arena, .limited(64 << 20));
    return program.decode(arena, try program.image.productFromExecutable(bytes));
}

fn arguments(arena: std.mem.Allocator, argv: []const []const u8) !Arguments {
    if (argv.len < 4 or argv.len > 136) return error.Usage;
    const action = std.meta.stringToEnum(runtime.Action, argv[1]) orelse return error.Usage;
    var root: ?[]const u8 = null;
    var failpoint: ?[]const u8 = null;
    var inputs: std.ArrayList(runtime.state.Value) = .empty;
    var index: usize = 2;
    while (index < argv.len) : (index += 2) {
        if (index + 1 >= argv.len) return error.Usage;
        const flag = argv[index];
        const value = argv[index + 1];
        if (std.mem.eql(u8, flag, "--root")) {
            if (root != null) return error.Usage;
            root = value;
        } else if (std.mem.eql(u8, flag, "--set")) {
            const equal = std.mem.indexOfScalar(u8, value, '=') orelse return error.Usage;
            try inputs.append(arena, .{ .id = value[0..equal], .value = value[equal + 1 ..] });
        } else if (std.mem.eql(u8, flag, "--failpoint")) {
            if (failpoint != null) return error.Usage;
            failpoint = value;
        } else return error.Usage;
    }
    return .{
        .action = action,
        .root = root orelse return error.Usage,
        .inputs = inputs.items,
        .failpoint = failpoint,
    };
}

const Fault = struct {
    io: std.Io,
    name: ?[]const u8,

    fn checkpoint(context: ?*anyopaque, name: []const u8) void {
        const self: *Fault = @ptrCast(@alignCast(context orelse return));
        const expected = self.name orelse return;
        if (!std.mem.eql(u8, expected, name)) return;
        std.Io.File.stderr().writeStreamingAll(self.io, "NIOBIUM_FAILPOINT\n") catch
            std.process.exit(2);
        // The acceptance parent receives the marker, then terminates the stopped child.
        if (raise(17) != 0) std.process.exit(2);
    }
};

extern "c" fn raise(signal: c_int) c_int;
