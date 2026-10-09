//! Install and run the pinned Rust and Go toolchains under `.cache/tools`.
//! Configuration does not touch the network; this program runs only when a step does.

const std = @import("std");
const builtin = @import("builtin");
const cache = @import("cache.zig");
const layout = @import("toolchain_layout.zig");
const archive = @import("toolchain_archive.zig");

const Dir = std.Io.Dir;
const max_download: u64 = 250 << 20;
const stamp_name = ".niobium-toolchain";

const Manifest = struct { tools: []const Tool };
const Tool = struct {
    id: []const u8,
    version: []const u8,
    platforms: []const Platform,
};
const Platform = struct {
    id: []const u8,
    artifacts: []const Artifact,
};
const Artifact = struct {
    url: []const u8,
    sha256: []const u8,
    role: layout.Role,
};

const Command = enum { install, doctor, run, require };

pub fn execute(init: std.process.Init, argv: []const []const u8) u8 {
    return dispatch(init, argv) catch |err| {
        std.debug.print("toolchain: {s}\n", .{@errorName(err)});
        return 1;
    };
}

fn dispatch(init: std.process.Init, argv: []const []const u8) !u8 {
    const arena = init.arena.allocator();
    const command = std.meta.stringToEnum(Command, if (argv.len >= 3) argv[2] else "") orelse {
        usage();
        return 2;
    };
    const flags = try parse(arena, argv[3..]);
    return switch (command) {
        .install => install(init, arena, flags),
        .doctor => doctor(init, arena, flags),
        .run => run(init, arena, flags),
        .require => require(init, flags),
    };
}

fn usage() void {
    std.debug.print(
        "usage: nb-fetch-deps toolchain install|doctor|run|require\n" ++
            "  [--root dir] [--manifest file] [--tool cargo|go]\n" ++
            "  [--name program] [--hint text] [-- args]\n",
        .{},
    );
}

const Flags = struct {
    root: []const u8 = ".cache/tools",
    manifest: []const u8 = ".zig/toolchains.zon",
    tool: []const u8 = "",
    name: []const u8 = "",
    hint: []const u8 = "",
    rest: []const []const u8 = &.{},
};

fn parse(arena: std.mem.Allocator, argv: []const []const u8) !Flags {
    var flags: Flags = .{};
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const flag = argv[index];
        if (std.mem.eql(u8, flag, "--")) {
            flags.rest = argv[index + 1 ..];
            return flags;
        }
        if (index + 1 >= argv.len) return error.UsageFetchDeps;
        const value = argv[index + 1];
        if (std.mem.eql(u8, flag, "--root")) {
            flags.root = value;
        } else if (std.mem.eql(u8, flag, "--manifest")) {
            flags.manifest = value;
        } else if (std.mem.eql(u8, flag, "--tool")) {
            flags.tool = value;
        } else if (std.mem.eql(u8, flag, "--name")) {
            flags.name = value;
        } else if (std.mem.eql(u8, flag, "--hint")) {
            flags.hint = value;
        } else return error.UsageFetchDeps;
        index += 1;
    }
    _ = arena;
    return flags;
}

fn install(init: std.process.Init, arena: std.mem.Allocator, flags: Flags) !u8 {
    const host = hostPlatform() orelse return unsupported();
    const manifest = try load(init.io, arena, flags.manifest);
    const deps = try cache.defaultCache(arena, init.environ_map);
    for (manifest.tools) |tool| {
        const platform = findPlatform(tool, host) orelse {
            std.debug.print("toolchain: {s} has no build for {s}\n", .{ tool.id, host });
            return 1;
        };
        try installTool(init, arena, flags.root, deps, tool, platform);
    }
    return 0;
}

fn installTool(
    init: std.process.Init,
    arena: std.mem.Allocator,
    root: []const u8,
    deps: []const u8,
    tool: Tool,
    platform: Platform,
) !void {
    const prefix = try std.fs.path.join(arena, &.{ root, tool.id, tool.version });
    if (try stampMatches(init.io, arena, prefix, platform.id, tool.version)) return;
    if (Dir.cwd().access(init.io, prefix, .{})) {
        try Dir.cwd().deleteTree(init.io, prefix);
    } else |err| {
        if (err != error.FileNotFound) return err;
    }
    var out = try Dir.cwd().createDirPathOpen(init.io, prefix, .{});
    defer out.close(init.io);
    for (platform.artifacts) |artifact| {
        const bytes = try cache.obtain(
            init.io,
            init.gpa,
            arena,
            init.environ_map,
            deps,
            artifact.url,
            artifact.sha256,
            max_download,
        );
        if (std.mem.endsWith(u8, artifact.url, ".zip")) {
            try archive.installZip(init.gpa, init.io, out, bytes, artifact.role);
        } else {
            try archive.installTarGz(arena, init.io, out, bytes, artifact.role);
        }
    }
    const text = try std.fmt.allocPrint(arena, "{s}\n{s}\n", .{ platform.id, tool.version });
    try out.writeFile(init.io, .{ .sub_path = stamp_name, .data = text });
}

fn doctor(init: std.process.Init, arena: std.mem.Allocator, flags: Flags) !u8 {
    const host = hostPlatform() orelse return unsupported();
    const manifest = try load(init.io, arena, flags.manifest);
    for (manifest.tools) |tool| {
        const platform = findPlatform(tool, host) orelse return 1;
        const prefix = try std.fs.path.join(arena, &.{ flags.root, tool.id, tool.version });
        if (!try stampMatches(init.io, arena, prefix, platform.id, tool.version)) {
            std.debug.print(
                "toolchain: {s} {s} is not installed. Run `zig build tools:install`.\n",
                .{ tool.id, tool.version },
            );
            return 1;
        }
        try checkVersion(init, arena, prefix, tool);
    }
    try reportHostCompiler(init);
    return 0;
}

fn checkVersion(
    init: std.process.Init,
    arena: std.mem.Allocator,
    prefix: []const u8,
    tool: Tool,
) !void {
    const bin = if (std.mem.eql(u8, tool.id, "go")) "go" else "rustc";
    const program = try binary(arena, prefix, bin);
    const result = try std.process.run(init.gpa, init.io, .{
        .argv = &.{ program, "--version" },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(60), .clock = .awake } },
    });
    defer init.gpa.free(result.stdout);
    defer init.gpa.free(result.stderr);
    const needle = if (std.mem.eql(u8, tool.id, "go"))
        try std.fmt.allocPrint(arena, "go{s}", .{tool.version})
    else
        tool.version;
    if (!result.term.success() or std.mem.indexOf(u8, result.stdout, needle) == null) {
        std.debug.print(
            "toolchain: {s} did not report {s}\n{s}\n",
            .{ program, needle, result.stderr },
        );
        return error.ToolchainVersion;
    }
}

fn run(init: std.process.Init, arena: std.mem.Allocator, flags: Flags) !u8 {
    if (flags.rest.len == 0) return error.UsageFetchDeps;
    const host = hostPlatform() orelse return unsupported();
    const manifest = try load(init.io, arena, flags.manifest);
    const resolved = try resolve(manifest, flags.tool);
    const platform = findPlatform(resolved.tool, host) orelse return 1;
    const prefix = try std.fs.path.join(arena, &.{
        flags.root, resolved.tool.id, resolved.tool.version,
    });
    if (!try stampMatches(init.io, arena, prefix, platform.id, resolved.tool.version)) {
        std.debug.print(
            "toolchain: {s} {s} is not installed. Run `zig build tools:install`.\n",
            .{ resolved.tool.id, resolved.tool.version },
        );
        return 1;
    }
    const program = try binary(arena, prefix, resolved.bin);
    const argv = try arena.alloc([]const u8, flags.rest.len + 1);
    argv[0] = program;
    @memcpy(argv[1..], flags.rest);
    var env: std.process.Environ.Map = .init(arena);
    try env.putAll(init.environ_map);
    try prependPath(arena, &env, try std.fs.path.join(arena, &.{ prefix, "bin" }));
    if (std.mem.eql(u8, resolved.tool.id, "rust")) {
        try env.put("CARGO_HOME", try std.fs.path.join(arena, &.{ flags.root, "cargo-home" }));
    } else {
        try env.put("GOROOT", prefix);
        try env.put("GOTOOLCHAIN", "local");
    }
    var child = try std.process.spawn(init.io, .{ .argv = argv, .environ_map = &env });
    const term = try child.wait(init.io);
    return if (term.success()) 0 else 1;
}

const Resolved = struct { tool: Tool, bin: []const u8 };

fn resolve(manifest: Manifest, name: []const u8) !Resolved {
    if (std.mem.eql(u8, name, "cargo") or std.mem.eql(u8, name, "rustc")) {
        return .{ .tool = try findTool(manifest, "rust"), .bin = name };
    }
    if (std.mem.eql(u8, name, "go")) return .{ .tool = try findTool(manifest, "go"), .bin = "go" };
    std.debug.print("toolchain: unknown tool {s}\n", .{name});
    return error.ToolchainTool;
}

fn require(init: std.process.Init, flags: Flags) !u8 {
    if (flags.name.len == 0) return error.UsageFetchDeps;
    if (try onPath(init, flags.name)) return 0;
    std.debug.print("{s} was not found on PATH.\n{s}\n", .{ flags.name, flags.hint });
    return 1;
}

fn reportHostCompiler(init: std.process.Init) !void {
    if (builtin.os.tag != .windows) return;
    const gcc = try onPath(init, "gcc");
    const dlltool = try onPath(init, "dlltool");
    if (gcc and dlltool) return;
    std.debug.print(
        "toolchain: gcc or dlltool is not on PATH. The Windows GNU publisher needs both; " ++
            "see docs/development/cross-host-builds.md.\n",
        .{},
    );
}

fn onPath(init: std.process.Init, name: []const u8) !bool {
    const path = init.environ_map.get("PATH") orelse return false;
    var parts = std.mem.splitScalar(u8, path, if (builtin.os.tag == .windows) ';' else ':');
    const file = if (builtin.os.tag == .windows and !std.mem.endsWith(u8, name, ".exe"))
        try std.fmt.allocPrint(init.arena.allocator(), "{s}.exe", .{name})
    else
        name;
    while (parts.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = try std.fs.path.join(init.arena.allocator(), &.{ dir, file });
        Dir.cwd().access(init.io, candidate, .{}) catch continue;
        return true;
    }
    return false;
}

fn prependPath(arena: std.mem.Allocator, env: *std.process.Environ.Map, bin: []const u8) !void {
    const old = env.get("PATH") orelse "";
    const sep: u8 = if (builtin.os.tag == .windows) ';' else ':';
    try env.put("PATH", try std.fmt.allocPrint(arena, "{s}{c}{s}", .{ bin, sep, old }));
}

fn stampMatches(
    io: std.Io,
    arena: std.mem.Allocator,
    prefix: []const u8,
    platform: []const u8,
    version: []const u8,
) !bool {
    const path = try std.fs.path.join(arena, &.{ prefix, stamp_name });
    const text = Dir.cwd().readFileAlloc(io, path, arena, .limited(512)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    var lines = std.mem.splitScalar(u8, text, '\n');
    const found_platform = lines.next() orelse return false;
    const found_version = lines.next() orelse return false;
    return std.mem.eql(u8, found_platform, platform) and std.mem.eql(u8, found_version, version);
}

fn binary(arena: std.mem.Allocator, prefix: []const u8, name: []const u8) ![]const u8 {
    const file = if (builtin.os.tag == .windows)
        try std.fmt.allocPrint(arena, "{s}.exe", .{name})
    else
        name;
    return std.fs.path.join(arena, &.{ prefix, "bin", file });
}

fn findTool(manifest: Manifest, id: []const u8) !Tool {
    for (manifest.tools) |tool| {
        if (std.mem.eql(u8, tool.id, id)) return tool;
    }
    return error.ToolchainTool;
}

fn findPlatform(tool: Tool, host: []const u8) ?Platform {
    for (tool.platforms) |platform| {
        if (std.mem.eql(u8, platform.id, host)) return platform;
    }
    return null;
}

fn hostPlatform() ?[]const u8 {
    const target = builtin.target;
    if (target.os.tag == .macos and target.cpu.arch == .aarch64) return "aarch64-apple-darwin";
    if (target.os.tag == .linux and target.cpu.arch == .x86_64 and target.abi == .gnu) {
        return "x86_64-unknown-linux-gnu";
    }
    if (target.os.tag == .windows and target.cpu.arch == .x86_64) return "x86_64-pc-windows-msvc";
    return null;
}

fn unsupported() u8 {
    std.debug.print(
        "toolchain: this host has no pinned Rust/Go build. Supported hosts are " ++
            "aarch64-apple-darwin, x86_64-unknown-linux-gnu, and x86_64-pc-windows-msvc.\n",
        .{},
    );
    return 1;
}

fn load(io: std.Io, arena: std.mem.Allocator, path: []const u8) !Manifest {
    const bytes = try Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 20));
    var diagnostics: std.zon.parse.Diagnostics = undefined; // SAFETY: filled by fromSlice.
    const manifest = std.zon.parse.fromSlice(Manifest, .{
        .gpa = arena,
        .arena = arena,
        .source = try arena.dupeSentinel(u8, bytes, 0),
        .diagnostics = &diagnostics,
    }) catch |err| {
        std.debug.print("toolchain: {f}\n", .{diagnostics.fmt(path)});
        return err;
    };
    if (manifest.tools.len == 0 or manifest.tools.len > 8) return error.FetchInvalidLimit;
    for (manifest.tools) |tool| {
        if (tool.platforms.len == 0 or tool.platforms.len > 8) return error.FetchInvalidLimit;
        for (tool.platforms) |platform| {
            if (platform.artifacts.len == 0 or platform.artifacts.len > 8) {
                return error.FetchInvalidLimit;
            }
            for (platform.artifacts) |artifact| try hash(artifact.sha256);
        }
    }
    return manifest;
}

fn hash(text: []const u8) !void {
    if (text.len != 64) return error.FetchInvalidHash;
    for (text) |byte| {
        const hex = std.ascii.isDigit(byte) or (byte >= 'a' and byte <= 'f');
        if (!hex) return error.FetchInvalidHash;
    }
}

test {
    _ = layout;
}
