//! Git hooks installed by `zig build hooks:install`.
//! pre-commit formats staged Zig. pre-push checks commit subjects.

const std = @import("std");
const builtin = @import("builtin");

const Dir = std.Io.Dir;
const hook_names = [_][]const u8{ "pre-commit", "commit-msg", "pre-push" };
const max_staged = 4096;
const max_refs = 64;
const max_stdin = 64 << 10;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) return error.Usage;
    if (std.mem.eql(u8, args[1], "install")) return install(init, arena);
    if (std.mem.eql(u8, args[1], "pre-commit")) {
        if (args.len < 3) return error.Usage;
        return preCommit(init, arena, args[2]);
    }
    if (std.mem.eql(u8, args[1], "pre-push")) {
        if (args.len < 3) return error.Usage;
        return prePush(init, arena, args[2]);
    }
    return error.Usage;
}

fn install(init: std.process.Init, arena: std.mem.Allocator) !void {
    const io = init.io;
    const hooks = try gitPath(init, arena, "--git-path", "hooks");
    var dest = try Dir.cwd().createDirPathOpen(io, hooks, .{});
    defer dest.close(io);
    try installHost(io, arena, &dest, builtin.os.tag == .windows);
    std.debug.print("installed git hooks in {s}\n", .{hooks});
}

fn installHost(io: std.Io, arena: std.mem.Allocator, dest: *Dir, windows: bool) !void {
    if (windows) return installWindows(io, arena, dest);
    for (hook_names) |name| {
        const source = try hookSource(arena, false, name);
        try copyHook(io, arena, dest, source, name);
    }
}

fn installWindows(io: std.Io, arena: std.mem.Allocator, dest: *Dir) !void {
    const launcher = try Dir.cwd().readFileAlloc(
        io,
        ".githooks/windows/launch.sh",
        arena,
        .limited(64 << 10),
    );
    for (hook_names) |name| {
        const source = try hookSource(arena, true, name);
        const cmd = try std.fmt.allocPrint(arena, "{s}.cmd", .{name});
        try copyHook(io, arena, dest, source, cmd);
        try writeHook(io, dest, name, launcher);
    }
}

fn hookSource(arena: std.mem.Allocator, windows: bool, name: []const u8) ![]const u8 {
    if (windows) return std.fmt.allocPrint(arena, ".githooks/windows/{s}.cmd", .{name});
    return std.fmt.allocPrint(arena, ".githooks/posix/{s}", .{name});
}

fn copyHook(
    io: std.Io,
    arena: std.mem.Allocator,
    dest: *Dir,
    source: []const u8,
    name: []const u8,
) !void {
    const bytes = try Dir.cwd().readFileAlloc(io, source, arena, .limited(64 << 10));
    try writeHook(io, dest, name, bytes);
}

fn writeHook(io: std.Io, dest: *Dir, name: []const u8, bytes: []const u8) !void {
    var file = try dest.createFile(io, name, .{ .permissions = .executable_file });
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
}

fn preCommit(init: std.process.Init, arena: std.mem.Allocator, zig_exe: []const u8) !void {
    const listed = try git(init, arena, &.{
        "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z",
    });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, zig_exe);
    try argv.append(arena, "fmt");
    try argv.append(arena, "--check");
    try argv.append(arena, "--ast-check");
    var names = std.mem.splitScalar(u8, listed, 0);
    var count: usize = 0;
    while (names.next()) |name| {
        if (name.len == 0 or !std.mem.endsWith(u8, name, ".zig")) continue;
        count += 1;
        if (count > max_staged) return error.TooManyFiles;
        try argv.append(arena, name);
    }
    if (count == 0) return;
    const result = try std.process.run(arena, init.io, .{
        .argv = argv.items,
        .stdout_limit = .limited(1 << 20),
        .stderr_limit = .limited(1 << 20),
    });
    if (!result.term.success()) {
        std.debug.print("{s}{s}", .{ result.stdout, result.stderr });
        return error.Format;
    }
}

fn prePush(init: std.process.Init, arena: std.mem.Allocator, checker: []const u8) !void {
    var buffer: [4096]u8 = undefined; // SAFETY: stdin reader scratch.
    var reader = std.Io.File.stdin().reader(init.io, &buffer);
    const text = try reader.interface.allocRemaining(arena, .limited(max_stdin));
    var lines = std.mem.splitScalar(u8, text, '\n');
    var seen: usize = 0;
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        seen += 1;
        if (seen > max_refs) return error.TooManyRefs;
        const update = try parseUpdate(line);
        if (update.delete) continue;
        const range = try pushRange(init, arena, update);
        try runChecker(init, arena, checker, range);
    }
}

const Update = struct {
    local_sha: []const u8,
    remote_sha: []const u8,
    delete: bool,
};

fn parseUpdate(line: []const u8) !Update {
    var fields = std.mem.splitScalar(u8, line, ' ');
    _ = fields.next() orelse return error.BadRefLine;
    const local_sha = fields.next() orelse return error.BadRefLine;
    _ = fields.next() orelse return error.BadRefLine;
    const remote_sha = fields.next() orelse return error.BadRefLine;
    if (fields.next() != null) return error.BadRefLine;
    if (!sha(local_sha) or !sha(remote_sha)) return error.BadRefLine;
    return .{
        .local_sha = local_sha,
        .remote_sha = remote_sha,
        .delete = zeros(local_sha),
    };
}

fn pushRange(init: std.process.Init, arena: std.mem.Allocator, update: Update) ![]const u8 {
    if (!zeros(update.remote_sha)) {
        return std.fmt.allocPrint(arena, "{s}..{s}", .{ update.remote_sha, update.local_sha });
    }
    const present = git(init, arena, &.{ "rev-parse", "--verify", "--quiet", "origin/main" });
    if (present) |_| {
        return std.fmt.allocPrint(arena, "origin/main..{s}", .{update.local_sha});
    } else |_| {
        std.debug.print(
            "hooks: origin/main is missing; fetch it before pushing a new branch\n",
            .{},
        );
        return error.NoUpstream;
    }
}

fn runChecker(
    init: std.process.Init,
    arena: std.mem.Allocator,
    checker: []const u8,
    range: []const u8,
) !void {
    const result = try std.process.run(arena, init.io, .{
        .argv = &.{ checker, range },
        .stdout_limit = .limited(1 << 20),
        .stderr_limit = .limited(1 << 20),
    });
    if (!result.term.success()) {
        std.debug.print("{s}{s}", .{ result.stdout, result.stderr });
        return error.CommitSubject;
    }
}

fn git(init: std.process.Init, arena: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    var full: std.ArrayList([]const u8) = .empty;
    try full.append(arena, "git");
    try full.appendSlice(arena, argv);
    const result = try std.process.run(arena, init.io, .{
        .argv = full.items,
        .stdout_limit = .limited(1 << 20),
        .stderr_limit = .limited(64 << 10),
    });
    if (!result.term.success()) {
        std.debug.print("{s}", .{result.stderr});
        return error.Git;
    }
    return std.mem.trimEnd(u8, result.stdout, "\r\n");
}

fn gitPath(
    init: std.process.Init,
    arena: std.mem.Allocator,
    flag: []const u8,
    name: []const u8,
) ![]const u8 {
    return git(init, arena, &.{ "rev-parse", flag, name });
}

fn sha(text: []const u8) bool {
    if (text.len != 40 and text.len != 64) return false;
    for (text) |byte| {
        const hex = std.ascii.isDigit(byte) or (byte >= 'a' and byte <= 'f');
        if (!hex) return false;
    }
    return true;
}

fn zeros(text: []const u8) bool {
    for (text) |byte| if (byte != '0') return false;
    return text.len != 0;
}

test "push lines name the commit range" {
    const zero = "0000000000000000000000000000000000000000";
    const local = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const remote = "cccccccccccccccccccccccccccccccccccccccc";
    const deleted = try std.fmt.allocPrint(
        std.testing.allocator,
        "refs/heads/main {s} refs/heads/main {s}",
        .{ zero, local },
    );
    defer std.testing.allocator.free(deleted);
    const created = try parseUpdate(deleted);
    try std.testing.expect(created.delete);
    const kept = try std.fmt.allocPrint(
        std.testing.allocator,
        "refs/heads/topic {s} refs/heads/topic {s}",
        .{ local, remote },
    );
    defer std.testing.allocator.free(kept);
    const update = try parseUpdate(kept);
    try std.testing.expect(!update.delete);
    try std.testing.expectEqualStrings(local, update.local_sha);
    try std.testing.expectError(error.BadRefLine, parseUpdate("only-three a b"));
}

test "hook scripts are split by platform" {
    const posix = try hookSource(std.testing.allocator, false, "commit-msg");
    defer std.testing.allocator.free(posix);
    const windows = try hookSource(std.testing.allocator, true, "commit-msg");
    defer std.testing.allocator.free(windows);
    try std.testing.expectEqualStrings(".githooks/posix/commit-msg", posix);
    try std.testing.expectEqualStrings(".githooks/windows/commit-msg.cmd", windows);
}

test "sha text is hex of a git length" {
    const sample = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const zeros_sha = "0000000000000000000000000000000000000000";
    try std.testing.expect(sha(sample));
    try std.testing.expect(zeros(zeros_sha));
    try std.testing.expect(!sha("gggggggggggggggggggggggggggggggggggggggg"));
    try std.testing.expect(!sha("abc"));
}
