//! N2-AUTH-01: independent language frontends must emit identical canonical programs.

const std = @import("std");
const program = @import("program");
const contracts = @import("contracts");

pub const Options = struct {
    author_zig: []const u8,
    author_c: []const u8,
    starlark: []const u8,
    source: []const u8,
    library_v1: []const u8,
    library_v2: []const u8,
    output_dir: []const u8,
};

pub const Programs = struct { v1: []const u8, v2: []const u8 };
pub const Error = program.Error || std.process.RunError || std.Io.Dir.CreateDirPathError ||
    std.Io.Dir.ReadFileAllocError || std.Io.Dir.WriteFileError || error{
    AuthoringFailed,
    AuthoringMismatch,
};

pub fn verify(arena: std.mem.Allocator, io: std.Io, options: Options) Error!Programs {
    try std.Io.Dir.cwd().createDirPath(io, options.output_dir);
    return .{
        .v1 = try release(arena, io, options, 1, options.library_v1),
        .v2 = try release(arena, io, options, 2, options.library_v2),
    };
}

fn release(
    arena: std.mem.Allocator,
    io: std.Io,
    options: Options,
    version: u32,
    library: []const u8,
) Error![]const u8 {
    const sequence = try arena.print("{d}", .{version});
    const zig_path = try arena.print("{s}/v{d}-zig.program", .{ options.output_dir, version });
    const c_path = try arena.print("{s}/v{d}-c.program", .{ options.output_dir, version });
    const star_path = try arena.print("{s}/v{d}-starlark.program", .{
        options.output_dir, version,
    });
    try command(arena, io, &.{ options.author_zig, library, zig_path, sequence }, zig_path);
    try command(arena, io, &.{ options.author_c, library, c_path, sequence }, c_path);
    try command(arena, io, &.{
        options.starlark, "--source", options.source, "--out",  star_path,
        "--library",      library,    "--version",    sequence,
    }, star_path);
    const native = try read(arena, io, zig_path);
    if (!std.mem.eql(u8, native, try read(arena, io, c_path))) return error.AuthoringMismatch;
    if (!std.mem.eql(u8, native, try read(arena, io, star_path))) return error.AuthoringMismatch;
    const model = try program.decode(arena, native);
    if (model.model_version != version or model.release_sequence != version) {
        return error.AuthoringMismatch;
    }
    if (model.inputs.len != 1 or model.resources.len != 1 or model.instances.len != 1) {
        return error.AuthoringMismatch;
    }
    if (!std.mem.eql(u8, model.inputs[0].default, "stable")) return error.AuthoringMismatch;
    if (!std.mem.eql(u8, model.resources[0].path, "toolchain.env")) return error.AuthoringMismatch;
    const migrations: usize = if (version == 2) 1 else 0;
    if (model.upgrades.len != migrations or model.instances[0].migrations.len != migrations) {
        return error.AuthoringMismatch;
    }
    return zig_path;
}

fn read(arena: std.mem.Allocator, io: std.Io, path: []const u8) Error![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(
        (contracts.Limits{}).program_bytes,
    ));
}

fn command(
    arena: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    output: []const u8,
) Error!void {
    const result = try std.process.run(arena, io, .{
        .argv = argv,
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } },
    });
    const record = try std.json.Stringify.valueAlloc(arena, .{
        .argv = argv,
        .term = result.term,
        .stdout = result.stdout,
        .stderr = result.stderr,
    }, .{});
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try arena.print("{s}.command.json", .{output}),
        .data = record,
        .flags = .{ .exclusive = true },
    });
    if (result.term != .exited or result.term.exited != 0) {
        std.log.err("author program failed: {s}", .{result.stderr});
        return error.AuthoringFailed;
    }
}
