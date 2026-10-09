//! Native subprocess witness. SIGKILL checkpoints exercise the real durable coordinator.
const std = @import("std");
const kernel = @import("kernel");
const platform = @import("platform");
const Fixture = @import("fixture.zig").Fixture;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 3 and args.len != 5) return error.Usage;
    const action = std.meta.stringToEnum(kernel.Action, args[1]) orelse return error.Usage;
    const dir = try std.Io.Dir.cwd().openDir(init.io, args[2], .{});
    defer dir.close(init.io);
    var fixture = try Fixture.init(arena, init.io, dir, 2);
    if (action == .update) {
        fixture.version = 2;
        try fixture.setContent("second");
    }
    var host: platform.Host = .init(init.io, .{ .env = .{}, .system_managers = false });
    var options = try fixture.options(&host, action);
    if (!action.needsProduct()) {
        options.model = null;
        options.evaluator = .{};
        options.content = .{};
    }
    var fault: Fault = .{
        .name = if (args.len == 5) args[3] else "",
        .root = if (args.len == 5) args[4] else "",
    };
    options.checkpoint = .{ .context = &fault, .call = Fault.reach };
    const result = try kernel.run(options);
    const bytes = try std.json.Stringify.valueAlloc(arena, result, .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, bytes);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}

const Fault = struct {
    name: []const u8,
    root: []const u8,

    fn reach(context: ?*anyopaque, name: []const u8, root: ?[]const u8) void {
        const self: *Fault = @ptrCast(@alignCast(context orelse return));
        if (!std.mem.eql(u8, name, self.name) or
            !std.mem.eql(u8, root orelse "", self.root)) return;
        if (comptime @import("builtin").os.tag == .windows) {
            const terminated = TerminateProcess(GetCurrentProcess(), 137);
            if (terminated == 0) std.process.exit(2);
        } else {
            const status = kill(getpid(), 9);
            if (status != 0) std.process.exit(2);
        }
    }
};

extern "c" fn getpid() c_int;
extern "c" fn kill(pid: c_int, signal: c_int) c_int;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) *anyopaque;
extern "kernel32" fn TerminateProcess(process: *anyopaque, status: u32) callconv(.winapi) c_int;
