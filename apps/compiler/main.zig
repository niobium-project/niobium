//! Assemble a generated product program into a prebuilt macOS runtime and sign final bytes.

const std = @import("std");
const compiler = @import("compiler");
const contracts = @import("contracts");
const program = @import("program");
const Dir = std.Io.Dir;

pub fn main(init: std.process.Init) u8 {
    run(init) catch |err| {
        std.log.err("niobium-compiler: {s}", .{@errorName(err)});
        return 1;
    };
    return 0;
}

const Options = struct { program: []const u8, runtime: []const u8, out: []const u8 };

fn options(args: []const []const u8) error{Usage}!Options {
    if (args.len != 7) return error.Usage;
    var result: Options = .{ .program = "", .runtime = "", .out = "" };
    var index: usize = 1;
    while (index < args.len) : (index += 2) {
        const destination = if (std.mem.eql(u8, args[index], "--program"))
            &result.program
        else if (std.mem.eql(u8, args[index], "--runtime"))
            &result.runtime
        else if (std.mem.eql(u8, args[index], "--out"))
            &result.out
        else
            return error.Usage;
        if (destination.len != 0 or args[index + 1].len == 0) return error.Usage;
        destination.* = args[index + 1];
    }
    if (result.program.len == 0 or result.runtime.len == 0 or result.out.len == 0) {
        return error.Usage;
    }
    return result;
}

fn run(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const request = try options(try init.minimal.args.toSlice(arena));
    const bytes = try Dir.cwd().readFileAlloc(io, request.program, arena, .limited(
        (contracts.Limits{}).program_bytes,
    ));
    const normalized = try compiler.compile(arena, bytes);
    const runtime = try Dir.cwd().readFileAlloc(io, request.runtime, arena, .limited(64 << 20));
    const executable = try program.image.embed(arena, runtime, normalized);
    const pending = try arena.print("{s}.pending", .{request.out});
    // Publish only verified bytes, and never replace an existing path or follow its symlink.
    try Dir.cwd().writeFile(io, .{
        .sub_path = pending,
        .data = executable,
        .flags = .{ .exclusive = true, .permissions = .fromMode(0o755) },
    });
    var published = false;
    defer if (!published) removePending(io, pending);
    try sign(arena, io, &.{ "/usr/bin/codesign", "--force", "--sign", "-", pending });
    try sign(arena, io, &.{ "/usr/bin/codesign", "--verify", "--strict", pending });
    try Dir.cwd().renamePreserve(pending, Dir.cwd(), request.out, io);
    published = true;
}

fn removePending(io: std.Io, pending: []const u8) void {
    Dir.cwd().deleteFile(io, pending) catch |err| {
        std.log.warn("cannot remove {s}: {s}", .{ pending, @errorName(err) });
    };
}

fn sign(arena: std.mem.Allocator, io: std.Io, argv: []const []const u8) !void {
    const result = try std.process.run(arena, io, .{
        .argv = argv,
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } },
    });
    if (result.term != .exited or result.term.exited != 0) {
        std.log.err("codesign: {s}", .{result.stderr});
        return error.SigningFailed;
    }
}

test "N2-IMAGE-01: CLI accepts generated IR and rejects repeated options" {
    const request = try options(&.{ "compiler", "--program", "p", "--runtime", "r", "--out", "o" });
    try std.testing.expectEqualStrings("p", request.program);
    try std.testing.expectError(error.Usage, options(&.{
        "compiler", "--program", "p", "--program", "r", "--out", "o",
    }));
}
