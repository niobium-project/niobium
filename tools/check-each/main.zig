//! `zig build check:each [-- <range>]` runs `zig build check` and `zig build` on each commit.
//! Default range is origin/main..HEAD, oldest first, at most `max_commits`. First failure stops.

const std = @import("std");
const builtin = @import("builtin");
const repo = @import("repo");

pub const max_commits = 64;
const max_scan = 8192;

const RangeError = error{
    Git,
    TooManyCommits,
    BadSha,
    Run,
};

pub const Failure = struct {
    sha: []const u8,
    step: []const u8,
};

pub const Request = struct {
    repo: []const u8,
    range: []const u8,
    zig_exe: []const u8,
    tmp_root: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2 or args.len > 3) return error.Usage;
    const range = if (args.len == 3) args[2] else "origin/main..HEAD";
    const failure = buildRange(init.io, arena, .{
        .repo = ".",
        .range = range,
        .zig_exe = args[1],
        .tmp_root = tmpRoot(init.environ_map),
    }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => |range_err| return reportError(init, range, range_err),
    };
    var report: repo.Report = .{ .arena = arena, .tool = "check-each" };
    if (failure) |found| {
        try report.add("{s}: zig build {s} failed", .{ found.sha, found.step });
    }
    try report.finish(init.io);
}

fn reportError(init: std.process.Init, range: []const u8, err: RangeError) !void {
    var report: repo.Report = .{ .arena = init.arena.allocator(), .tool = "check-each" };
    switch (err) {
        error.TooManyCommits => try report.add(
            "more than {d} commits in {s}",
            .{ max_commits, range },
        ),
        error.BadSha => try report.add("rev-list returned a non-sha in {s}", .{range}),
        error.Git => try report.add("git failed for {s}", .{range}),
        error.Run => try report.add("could not run zig build in {s}", .{range}),
    }
    try report.finish(init.io);
}

pub fn tmpRoot(env: *const std.process.Environ.Map) []const u8 {
    if (env.get("TMPDIR")) |value| if (value.len != 0) return value;
    if (env.get("TEMP")) |value| if (value.len != 0) return value;
    if (env.get("TMP")) |value| if (value.len != 0) return value;
    if (builtin.os.tag == .windows) return ".";
    return "/tmp";
}

pub fn buildRange(
    io: std.Io,
    arena: std.mem.Allocator,
    request: Request,
) (RangeError || std.mem.Allocator.Error)!?Failure {
    std.debug.assert(request.repo.len > 0);
    std.debug.assert(request.zig_exe.len > 0);
    std.debug.assert(request.tmp_root.len > 0);
    const listed = try gitStdout(io, arena, &.{
        "git", "-C", request.repo, "rev-list", "--reverse", request.range,
    });
    var shas: [max_commits][]const u8 = undefined; // SAFETY: takeShas fills count entries.
    const count = try takeShas(listed, &shas);
    if (count == 0) return null;
    const path = try worktreePath(io, arena, request.tmp_root);
    try gitOk(io, arena, &.{
        "git", "-C", request.repo, "worktree", "add", "--detach", path, shas[0],
    });
    defer removeWorktree(io, arena, request.repo, path);
    return try buildShas(io, arena, request, path, shas[0..count]);
}

fn buildShas(
    io: std.Io,
    arena: std.mem.Allocator,
    request: Request,
    path: []const u8,
    shas: []const []const u8,
) (RangeError || std.mem.Allocator.Error)!?Failure {
    std.debug.assert(shas.len > 0);
    std.debug.assert(shas.len <= max_commits);
    for (shas, 0..) |sha, index| {
        if (index != 0) {
            try gitOk(io, arena, &.{ "git", "-C", path, "checkout", "--detach", sha });
        }
        std.debug.print("check-each: {s}\n", .{sha});
        if (try zigFailed(io, arena, request.zig_exe, path, "check")) {
            return .{ .sha = sha, .step = "check" };
        }
        if (try zigFailed(io, arena, request.zig_exe, path, null)) {
            return .{ .sha = sha, .step = "build" };
        }
    }
    return null;
}

pub fn takeShas(text: []const u8, out: [][]const u8) error{ TooManyCommits, BadSha }!usize {
    std.debug.assert(out.len > 0);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var count: usize = 0;
    var seen: usize = 0;
    while (lines.next()) |raw| {
        seen += 1;
        if (seen > max_scan) return error.TooManyCommits;
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        if (count == out.len) return error.TooManyCommits;
        if (!isSha(line)) return error.BadSha;
        out[count] = line;
        count += 1;
    }
    return count;
}

fn worktreePath(io: std.Io, arena: std.mem.Allocator, root: []const u8) ![]const u8 {
    var bytes: [6]u8 = undefined; // SAFETY: io.random writes every byte.
    io.random(&bytes);
    var name: [12]u8 = undefined; // SAFETY: the loop writes every byte.
    const hex = "0123456789abcdef";
    for (bytes, 0..) |byte, index| {
        name[index * 2] = hex[byte >> 4];
        name[index * 2 + 1] = hex[byte & 0xf];
    }
    return std.fs.path.join(arena, &.{ root, &name });
}

fn zigFailed(
    io: std.Io,
    arena: std.mem.Allocator,
    zig_exe: []const u8,
    cwd: []const u8,
    step: ?[]const u8,
) (error{Run} || std.mem.Allocator.Error)!bool {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, zig_exe);
    try argv.append(arena, "build");
    if (step) |name| try argv.append(arena, name);
    const result = std.process.run(arena, io, .{
        .argv = argv.items,
        .cwd = .{ .path = cwd },
        .stdout_limit = .limited(8 << 20),
        .stderr_limit = .limited(8 << 20),
    }) catch return error.Run;
    if (result.term.success()) return false;
    std.debug.print("{s}{s}", .{ result.stdout, result.stderr });
    return true;
}

fn gitStdout(
    io: std.Io,
    arena: std.mem.Allocator,
    argv: []const []const u8,
) (error{Git} || std.mem.Allocator.Error)![]const u8 {
    std.debug.assert(argv.len > 0);
    const result = std.process.run(arena, io, .{
        .argv = argv,
        .stdout_limit = .limited(1 << 20),
        .stderr_limit = .limited(64 << 10),
    }) catch return error.Git;
    if (!result.term.success()) {
        std.debug.print("{s}", .{result.stderr});
        return error.Git;
    }
    return std.mem.trimEnd(u8, result.stdout, "\r\n");
}

fn gitOk(io: std.Io, arena: std.mem.Allocator, argv: []const []const u8) !void {
    const text = try gitStdout(io, arena, argv);
    std.debug.assert(text.len <= (1 << 20));
}

fn removeWorktree(
    io: std.Io,
    arena: std.mem.Allocator,
    repo_path: []const u8,
    path: []const u8,
) void {
    const result = std.process.run(arena, io, .{
        .argv = &.{ "git", "-C", repo_path, "worktree", "remove", "--force", path },
        .stdout_limit = .limited(64 << 10),
        .stderr_limit = .limited(64 << 10),
    }) catch |err| {
        std.debug.print("check-each: worktree remove failed: {s}\n", .{@errorName(err)});
        return;
    };
    if (!result.term.success()) {
        std.debug.print("check-each: {s}\n", .{result.stderr});
    }
}

fn isSha(text: []const u8) bool {
    if (text.len != 40 and text.len != 64) return false;
    for (text) |byte| {
        const hex = std.ascii.isDigit(byte) or (byte >= 'a' and byte <= 'f');
        if (!hex) return false;
    }
    return true;
}

test "sha list rejects overflow and non-shas" {
    var two: [2][]const u8 = undefined;
    const one = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const two_sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const count = try takeShas(one ++ "\n" ++ two_sha ++ "\n", &two);
    try std.testing.expectEqual(2, count);
    const extra = one ++ "\n" ++ two_sha ++ "\n" ++ one;
    try std.testing.expectError(error.TooManyCommits, takeShas(extra, &two));
    try std.testing.expectError(error.BadSha, takeShas("not-a-sha\n", &two));
}

const good_build =
    \\const std = @import("std");
    \\pub fn build(b: *std.Build) void {
    \\    _ = b.step("check", "ok");
    \\}
;

const broken_build =
    \\const std = @import("std");
    \\pub fn build(b: *std.Build) void {
    \\    const check = b.step("check", "broken");
    \\    const fail = b.addSystemCommand(&.{ "zig", "build-exe" });
    \\    check.dependOn(&fail.step);
    \\}
;

test "middle commit is the first build failure" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;
    var env = try std.testing.environ.createMap(arena);
    defer env.deinit();
    var repo_tmp = std.testing.tmpDir(.{});
    defer repo_tmp.cleanup();
    const repo_path = try repo_tmp.dir.realPathFileAlloc(io, ".", arena);
    try initRepo(io, arena, repo_path);
    try repo_tmp.dir.writeFile(io, .{ .sub_path = "build.zig", .data = good_build });
    _ = try commitFile(io, arena, repo_path, "feat(repo): start");
    try repo_tmp.dir.writeFile(io, .{ .sub_path = "build.zig", .data = broken_build });
    const bad = try commitFile(io, arena, repo_path, "feat(repo): break the check");
    try repo_tmp.dir.writeFile(io, .{ .sub_path = "build.zig", .data = good_build });
    _ = try commitFile(io, arena, repo_path, "feat(repo): restore the check");
    const failure = try buildRange(io, arena, .{
        .repo = repo_path,
        .range = "HEAD",
        .zig_exe = "zig",
        .tmp_root = tmpRoot(&env),
    });
    const found = failure orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings(bad, found.sha);
    try std.testing.expectEqualStrings("check", found.step);
}

fn initRepo(io: std.Io, arena: std.mem.Allocator, repo_path: []const u8) !void {
    try gitOk(io, arena, &.{ "git", "init", repo_path });
    try gitOk(io, arena, &.{ "git", "-C", repo_path, "config", "user.email", "dev@example.com" });
    try gitOk(io, arena, &.{ "git", "-C", repo_path, "config", "user.name", "Dev" });
    try gitOk(io, arena, &.{ "git", "-C", repo_path, "config", "commit.gpgsign", "false" });
}

fn commitFile(
    io: std.Io,
    arena: std.mem.Allocator,
    repo_path: []const u8,
    message: []const u8,
) ![]const u8 {
    try gitOk(io, arena, &.{ "git", "-C", repo_path, "add", "build.zig" });
    try gitOk(io, arena, &.{ "git", "-C", repo_path, "commit", "-m", message });
    return gitStdout(io, arena, &.{ "git", "-C", repo_path, "rev-parse", "HEAD" });
}
