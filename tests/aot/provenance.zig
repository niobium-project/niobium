//! Local suite provenance follows the bounded Git capture used by tools/evidence/execute.zig.

const std = @import("std");
const builtin = @import("builtin");
const core = @import("core");
const Dir = std.Io.Dir;

const Source = struct { path: []const u8, kind: []const u8, sha256: ?[]const u8, bytes: u64 };
const Report = struct {
    schema: u32 = 1,
    suite: []const u8 = "aot",
    argv: []const []const u8,
    target: []const u8,
    started_ms: i64,
    finished_ms: ?i64 = null,
    status: []const u8 = "NOT_RUN",
    exit_code: ?u8 = null,
    failure: ?[]const u8 = null,
    revision: ?[]const u8 = null,
    dirty: ?bool = null,
    git_status_sha256: ?[]const u8 = null,
    source_identity_sha256: ?[]const u8 = null,
    source_files: []const Source = &.{},
    executable_sha256: ?[]const u8 = null,
};

pub const Run = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    repo: []const u8,
    evidence: []const u8,
    report: Report,

    pub fn start(arena: std.mem.Allocator, io: std.Io, argv: []const []const u8) !Run {
        return startForSuite(arena, io, argv, "aot");
    }

    pub fn startForSuite(
        arena: std.mem.Allocator,
        io: std.Io,
        argv: []const []const u8,
        suite: []const u8,
    ) !Run {
        if (suite.len == 0 or suite.len > 32) return error.EvidenceSuite;
        for (suite) |byte| {
            if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte) and byte != '-') {
                return error.EvidenceSuite;
            }
        }
        const now = std.Io.Clock.real.now(io).toMilliseconds();
        var stamp: std.Io.Writer.Allocating = .init(arena);
        try core.crash.writeUtc(&stamp.writer, @divTrunc(now, 1000));
        var random: [8]u8 = undefined; // SAFETY: random fills the suffix.
        io.random(&random);
        const repo = try Dir.cwd().realPathFileAlloc(io, ".", arena);
        const base = try arena.print("{s}/.evidence/{s}", .{ repo, suite });
        try Dir.cwd().createDirPath(io, base);
        const evidence = try arena.print("{s}/{s}-{s}", .{
            base, stamp.written(), std.fmt.bytesToHex(random, .lower),
        });
        try Dir.cwd().createDir(io, evidence, .default_dir);
        var run: Run = .{ .arena = arena, .io = io, .repo = repo, .evidence = evidence, .report = .{
            .suite = suite,
            .argv = argv,
            .target = @tagName(builtin.target.cpu.arch) ++ "-" ++ @tagName(builtin.target.os.tag),
            .started_ms = now,
        } };
        try run.save();
        return run;
    }

    pub fn capture(run: *Run) !void {
        run.report.revision = std.mem.trim(u8, try run.git(&.{ "rev-parse", "HEAD" }), "\r\n");
        const status = try run.git(&.{ "status", "--porcelain=v1", "-z", "--untracked-files=all" });
        run.report.dirty = status.len != 0;
        run.report.git_status_sha256 = try digest(run.arena, status);
        const paths = try run.git(&.{
            "ls-files", "-z", "--cached", "--others", "--exclude-standard",
        });
        var files: std.ArrayList(Source) = .empty;
        var iterator = std.mem.splitScalar(u8, paths, 0);
        var total: u64 = 0;
        while (iterator.next()) |path| {
            if (path.len == 0) continue;
            if (path.len > 1024 or files.items.len >= 4096) return error.EvidenceLimit;
            const entry = try run.source(path);
            total += entry.bytes;
            if (total > 64 << 20) return error.EvidenceLimit;
            try files.append(run.arena, entry);
        }
        std.mem.sort(Source, files.items, {}, struct {
            fn less(_: void, a: Source, b: Source) bool {
                return std.mem.lessThan(u8, a.path, b.path);
            }
        }.less);
        run.report.source_files = files.items;
        const identity = try std.json.Stringify.valueAlloc(run.arena, .{
            .revision = run.report.revision,
            .status = run.report.git_status_sha256,
            .files = files.items,
        }, .{});
        run.report.source_identity_sha256 = try digest(run.arena, identity);
        const executable = try Dir.cwd().readFileAlloc(
            run.io,
            run.report.argv[0],
            run.arena,
            .limited(30 << 20),
        );
        run.report.executable_sha256 = try digest(run.arena, executable);
        try run.save();
    }

    pub fn finish(run: *Run, failure: ?[]const u8) !void {
        run.report.finished_ms = std.Io.Clock.real.now(run.io).toMilliseconds();
        run.report.status = if (failure == null) "PASS" else "FAIL";
        run.report.exit_code = if (failure == null) 0 else 1;
        run.report.failure = failure;
        try run.save();
    }

    fn save(run: *Run) !void {
        const bytes = try std.json.Stringify.valueAlloc(run.arena, run.report, .{});
        if (bytes.len > 8 << 20) return error.EvidenceLimit;
        const path = try std.fs.path.join(run.arena, &.{ run.evidence, "metadata.json" });
        var atomic = try Dir.cwd().createFileAtomic(run.io, path, .{ .replace = true });
        defer atomic.deinit(run.io);
        try atomic.file.writeStreamingAll(run.io, bytes);
        try atomic.file.sync(run.io);
        try atomic.replace(run.io);
    }

    fn git(run: *Run, arguments: []const []const u8) ![]const u8 {
        const argv = try gitArguments(run.arena, builtin.target.os.tag, run.repo, arguments);
        const result = try std.process.run(run.arena, run.io, .{
            .argv = argv,
            .stdout_limit = .limited(4 << 20),
            .stderr_limit = .limited(4096),
            .timeout = .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } },
        });
        if (!result.term.success()) return error.SourceIdentityUnavailable;
        return result.stdout;
    }

    fn source(run: *Run, path: []const u8) !Source {
        const stat = Dir.cwd().statFile(run.io, path, .{ .follow_symlinks = false }) catch |err|
            switch (err) {
                error.FileNotFound => return .{
                    .path = path,
                    .kind = "deleted",
                    .sha256 = null,
                    .bytes = 0,
                },
                else => return err,
            };
        var link: [1024]u8 = undefined; // SAFETY: readLink initializes the returned slice.
        const bytes = if (stat.kind == .sym_link)
            link[0..try Dir.cwd().readLink(run.io, path, &link)]
        else if (stat.kind == .file)
            try regularBytes(run.arena, run.io, path)
        else
            return error.SourceKindUnsupported;
        return .{
            .path = path,
            .kind = @tagName(stat.kind),
            .sha256 = try digest(run.arena, bytes),
            .bytes = bytes.len,
        };
    }
};

fn gitArguments(
    arena: std.mem.Allocator,
    os: std.Target.Os.Tag,
    repo: []const u8,
    arguments: []const []const u8,
) std.mem.Allocator.Error![]const []const u8 {
    const executable = if (os == .windows) "git.exe" else "/usr/bin/git";
    return std.mem.concat(arena, []const u8, &.{
        &.{ executable, "-C", repo }, arguments,
    });
}

test "provenance selects the platform Git executable and preserves argument boundaries" {
    for ([_]std.Target.Os.Tag{ .windows, .linux, .macos }) |os| {
        const repo = "repository with spaces & literal";
        const argv = try gitArguments(std.testing.allocator, os, repo, &.{ "rev-parse", "HEAD" });
        defer std.testing.allocator.free(argv);
        const executable = if (os == .windows) "git.exe" else "/usr/bin/git";
        try std.testing.expectEqualDeep(
            @as([]const []const u8, &.{ executable, "-C", repo, "rev-parse", "HEAD" }),
            argv,
        );
    }
}

fn regularBytes(arena: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    const file = try Dir.cwd().openFile(io, path, .{ .follow_symlinks = false });
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.kind != .file or stat.size > 8 << 20) return error.EvidenceLimit;
    const size = std.math.cast(usize, stat.size) orelse return error.EvidenceLimit;
    const bytes = try arena.alloc(u8, size);
    if (try file.readPositionalAll(io, bytes, 0) != size) return error.SourceChanged;
    return bytes;
}

fn digest(arena: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var hash: [32]u8 = undefined; // SAFETY: hash fills the complete digest.
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    return arena.dupe(u8, &std.fmt.bytesToHex(hash, .lower));
}
