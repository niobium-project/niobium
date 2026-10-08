//! Evidence and process boundary for the real macOS AOT acceptance suite.

const std = @import("std");
const core = @import("core");
const program = @import("program");
const runtime = @import("runtime");
const Dir = std.Io.Dir;

pub const Tools = struct {
    runtime: []const u8,
    compiler: []const u8,
    author_zig: []const u8,
    author_c: []const u8,
    starlark: []const u8,
    source: []const u8,
    managed: []const u8,
    env_v1: []const u8,
    env_v2: []const u8,
    check_binary: []const u8,
};

pub const World = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    tools: Tools,
    repo: []const u8,
    evidence: []const u8,
    isolated: []const u8,
    env: std.process.Environ.Map,
    index: u32 = 0,

    pub fn init(process: std.process.Init, argv: []const []const u8) !World {
        if (argv.len != 11) return error.Usage;
        const arena = process.arena.allocator();
        const io = process.io;
        var tools: Tools = undefined; // SAFETY: each field is assigned by the bounded loop.
        inline for (comptime std.meta.fieldNames(Tools), 1..) |field, index| {
            @field(tools, field) = try Dir.cwd().realPathFileAlloc(io, argv[index], arena);
        }
        const repo = try Dir.cwd().realPathFileAlloc(io, ".", arena);
        var stamp: std.Io.Writer.Allocating = .init(arena);
        try core.crash.writeUtc(&stamp.writer, std.Io.Clock.real.now(io).toSeconds());
        const base = try arena.print("{s}/.evidence/aot", .{repo});
        try Dir.cwd().createDirPath(io, base);
        const evidence = try arena.print("{s}/{s}", .{ base, stamp.written() });
        try Dir.cwd().createDir(io, evidence, .default_dir);
        var random: [8]u8 = undefined; // SAFETY: random initializes every byte.
        io.random(&random);
        const isolated = try arena.print("/private/tmp/niobium-aot-{s}", .{
            try program.encodeHex(arena, &random),
        });
        try Dir.cwd().createDir(io, isolated, .default_dir);
        var env: std.process.Environ.Map = .init(arena);
        try env.put("PATH", "/usr/bin:/bin");
        try env.put("TMPDIR", isolated);
        return .{
            .arena = arena,
            .io = io,
            .tools = tools,
            .repo = repo,
            .evidence = evidence,
            .isolated = isolated,
            .env = env,
        };
    }

    pub fn path(w: *World, name: []const u8) ![]const u8 {
        return std.fs.path.join(w.arena, &.{ w.evidence, name });
    }

    pub fn temporary(w: *World, name: []const u8) ![]const u8 {
        return std.fs.path.join(w.arena, &.{ w.isolated, name });
    }

    pub fn read(w: *World, path_: []const u8) ![]const u8 {
        return Dir.cwd().readFileAlloc(w.io, path_, w.arena, .limited(64 << 20));
    }

    pub fn write(w: *World, path_: []const u8, bytes: []const u8) !void {
        try Dir.cwd().writeFile(w.io, .{ .sub_path = path_, .data = bytes });
    }

    pub fn copy(w: *World, from: []const u8, to: []const u8) !void {
        try Dir.cwd().copyFile(from, Dir.cwd(), to, w.io, .{ .replace = false });
    }

    pub fn exists(w: *World, path_: []const u8) !bool {
        Dir.cwd().access(w.io, path_, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        return true;
    }

    pub fn remove(w: *World, path_: []const u8) !void {
        try Dir.cwd().deleteFile(w.io, path_);
    }

    pub fn run(w: *World, argv: []const []const u8, success: bool) !std.process.RunResult {
        if (w.index >= 1000) return error.EvidenceLimit;
        const result = try std.process.run(w.arena, w.io, .{
            .argv = argv,
            .cwd = .{ .path = w.isolated },
            .environ_map = &w.env,
            .stdout_limit = .limited(4 << 20),
            .stderr_limit = .limited(4 << 20),
            .timeout = .{ .duration = .{ .raw = .fromSeconds(45), .clock = .awake } },
        });
        try w.record(.{
            .argv = argv,
            .term = result.term,
            .stdout = result.stdout,
            .stderr = result.stderr,
        });
        if (result.term.success() != success) {
            std.log.err("unexpected exit from {s}: {t}; {s}", .{
                argv[0], result.term, result.stderr,
            });
            return error.CommandFailed;
        }
        return result;
    }

    pub fn command(w: *World, argv: []const []const u8, success: bool) !void {
        const result = try w.run(argv, success);
        std.debug.assert(result.term.success() == success);
    }

    pub fn record(w: *World, value: anytype) !void {
        const name = try w.arena.print("command-{d:0>3}.json", .{w.index});
        w.index += 1;
        try w.write(try w.path(name), try std.json.Stringify.valueAlloc(w.arena, value, .{}));
    }

    pub fn case(w: *World, id: []const u8, name: []const u8, outcome: []const u8) !void {
        const filename = try w.arena.print("{s}-{s}.json", .{ id, name });
        try w.write(try w.path(filename), try std.json.Stringify.valueAlloc(w.arena, .{
            .id = id,
            .case = name,
            .status = outcome,
        }, .{}));
    }

    pub fn hash(w: *World, path_: []const u8) ![]const u8 {
        var digest: [32]u8 = undefined; // SAFETY: hash initializes every byte.
        std.crypto.hash.sha2.Sha256.hash(try w.read(path_), &digest, .{});
        return program.encodeHex(w.arena, &digest);
    }

    pub fn status(
        w: *World,
        exe: []const u8,
        root: []const u8,
        action: []const u8,
    ) !runtime.Result {
        const result = try w.run(&.{ exe, action, "--root", root }, true);
        return std.json.parseFromSliceLeaky(runtime.Result, w.arena, result.stdout, .{});
    }

    pub fn expectFile(w: *World, path_: []const u8, expected: []const u8) !void {
        if (!std.mem.eql(u8, try w.read(path_), expected)) return error.FileMismatch;
    }
};

pub fn expect(condition: bool) error{AcceptanceMismatch}!void {
    if (!condition) return error.AcceptanceMismatch;
}
