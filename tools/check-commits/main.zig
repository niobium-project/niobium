//! Commit message lint (`zig build check:commits [-- --strict] [-- <range>]`).
//! Default range: origin/main..HEAD. `--message-file` checks one commit message.
//! Default mode skips merge commits and accepts fixup subjects.
//! `--strict` rejects merges, fixup subjects, and commits with no signature header.

const std = @import("std");
const repo = @import("repo");

pub const types = [_][]const u8{
    "feat", "fix", "test", "docs", "refactor", "chore", "adr", "build", "revert",
};

/// `git commit --fixup`, `--squash`, and `--amend` subjects. The text after the prefix
/// still has to be a valid subject. Strict history checks reject the prefix itself.
pub const fixup_prefixes = [_][]const u8{ "fixup! ", "squash! ", "amend! " };

pub const max_subject_bytes = 200;
pub const max_listed = 4096;
pub const max_header_lines = 256;

const Parsed = struct {
    message_file: ?[]const u8 = null,
    strict: bool = false,
    range: []const u8 = "origin/main..HEAD",
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const parsed = try parseArgs(args);
    if (parsed.message_file) |path| return checkMessage(init, path, parsed.strict);
    if (parsed.strict) return checkStrict(init, parsed.range);
    return checkSubjects(init, parsed.range);
}

fn parseArgs(args: []const []const u8) error{Usage}!Parsed {
    var parsed: Parsed = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--strict")) {
            parsed.strict = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--message-file")) {
            index += 1;
            if (index >= args.len) return error.Usage;
            parsed.message_file = args[index];
            continue;
        }
        if (arg.len > 0 and arg[0] == '-') return error.Usage;
        parsed.range = arg;
    }
    return parsed;
}

fn checkSubjects(init: std.process.Init, range: []const u8) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const result = try std.process.run(arena, io, .{
        .argv = &.{ "git", "log", "--no-merges", "--format=%h %s", range },
        .stdout_limit = .limited(4 << 20),
        .stderr_limit = .limited(64 << 10),
    });
    var report: repo.Report = .{ .arena = arena, .tool = "check-commits" };
    if (!result.term.success()) {
        try report.add("git log {s} failed: {s}", .{ range, result.stderr });
        return report.finish(io);
    }
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const space = std.mem.findScalar(u8, line, ' ') orelse continue;
        const subject = line[space + 1 ..];
        if (validate(subject)) |reason| try report.add(
            "{s}: {s}: '{s}'",
            .{ line[0..space], reason, subject },
        );
    }
    try report.finish(io);
}

fn checkStrict(init: std.process.Init, range: []const u8) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    var report: repo.Report = .{ .arena = arena, .tool = "check-commits" };
    const listed = try gitText(arena, io, &.{ "log", "--format=%H", range });
    if (listed.err) |stderr| {
        try report.add("git log {s} failed: {s}", .{ range, stderr });
        return report.finish(io);
    }
    var lines = std.mem.splitScalar(u8, listed.stdout, '\n');
    var count: usize = 0;
    while (lines.next()) |hash| {
        if (hash.len == 0) continue;
        count += 1;
        if (count > max_listed) {
            try report.add("more than {d} commits in {s}", .{ max_listed, range });
            break;
        }
        try judgeHash(arena, io, &report, hash);
    }
    try report.finish(io);
}

fn judgeHash(
    arena: std.mem.Allocator,
    io: std.Io,
    report: *repo.Report,
    hash: []const u8,
) !void {
    const object = try gitText(arena, io, &.{ "cat-file", "commit", hash });
    const label = if (hash.len > 12) hash[0..12] else hash;
    if (object.err) |stderr| {
        try report.add("{s}: git cat-file failed: {s}", .{ label, stderr });
        return;
    }
    const view = inspectCommit(object.stdout) catch {
        try report.add("{s}: unreadable commit", .{label});
        return;
    };
    if (strictReason(view)) |reason| {
        try report.add("{s}: {s}: '{s}'", .{ label, reason, view.subject });
    }
}

const GitText = struct {
    stdout: []const u8 = "",
    err: ?[]const u8 = null,
};

fn gitText(arena: std.mem.Allocator, io: std.Io, argv: []const []const u8) !GitText {
    var full: std.ArrayList([]const u8) = .empty;
    try full.append(arena, "git");
    try full.appendSlice(arena, argv);
    const result = try std.process.run(arena, io, .{
        .argv = full.items,
        .stdout_limit = .limited(4 << 20),
        .stderr_limit = .limited(64 << 10),
    });
    if (!result.term.success()) {
        return .{ .err = std.mem.trimEnd(u8, result.stderr, "\r\n") };
    }
    return .{ .stdout = result.stdout };
}

fn checkMessage(init: std.process.Init, path: []const u8, strict: bool) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 20));
    var report: repo.Report = .{ .arena = arena, .tool = "check-commits" };
    if (acceptMode(text, strict)) |reason| {
        const subject = messageSubject(text) orelse "";
        try report.add("{s}: '{s}'", .{ reason, subject });
    }
    try report.finish(io);
}

/// Null when the message may be committed: empty, comments only, a merge, or a valid subject.
pub fn acceptMessage(text: []const u8) ?[]const u8 {
    return acceptMode(text, false);
}

fn acceptMode(text: []const u8, strict: bool) ?[]const u8 {
    const subject = messageSubject(text) orelse return null;
    if (std.mem.startsWith(u8, subject, "Merge ")) {
        if (strict) return "merge commit";
        return null;
    }
    if (strict) return validateStrict(subject);
    return validate(subject);
}

fn messageSubject(text: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0 or line[0] == '#') continue;
        return line;
    }
    return null;
}

/// Returns null when the subject is valid, else the reason.
/// A fixup, squash, or amend prefix is accepted when the remainder is a valid subject.
pub fn validate(subject: []const u8) ?[]const u8 {
    return validateCore(subjectBody(subject));
}

fn subjectBody(subject: []const u8) []const u8 {
    for (fixup_prefixes) |prefix| {
        if (std.mem.startsWith(u8, subject, prefix)) return subject[prefix.len..];
    }
    return subject;
}

/// Strict history: no fixup prefix, then the same subject rules as `validate`.
pub fn validateStrict(subject: []const u8) ?[]const u8 {
    if (subjectBody(subject).len != subject.len) return "fixup subject";
    return validateCore(subject);
}

pub const CommitView = struct {
    subject: []const u8,
    parents: u8,
    signed: bool,
};

/// Reads one `git cat-file commit` object. A signature is `gpgsig` or `gpgsig-sha256`.
pub fn inspectCommit(text: []const u8) error{BadCommit}!CommitView {
    const split = std.mem.indexOf(u8, text, "\n\n") orelse return error.BadCommit;
    const header = text[0..split];
    var parents: u8 = 0;
    var signed = false;
    var lines = std.mem.splitScalar(u8, header, '\n');
    var seen: usize = 0;
    while (lines.next()) |line| {
        seen += 1;
        if (seen > max_header_lines) return error.BadCommit;
        if (std.mem.startsWith(u8, line, "parent ")) {
            if (parents == std.math.maxInt(u8)) return error.BadCommit;
            parents += 1;
        } else if (signatureHeader(line)) {
            signed = true;
        }
    }
    return .{
        .subject = firstLine(text[split + 2 ..]),
        .parents = parents,
        .signed = signed,
    };
}

fn signatureHeader(line: []const u8) bool {
    if (std.mem.startsWith(u8, line, "gpgsig-sha256 ")) return true;
    return std.mem.startsWith(u8, line, "gpgsig ");
}

fn firstLine(message: []const u8) []const u8 {
    const end = std.mem.findScalar(u8, message, '\n') orelse message.len;
    return std.mem.trimEnd(u8, message[0..end], "\r");
}

/// One reason a commit cannot land on main, or null when it can.
pub fn strictReason(view: CommitView) ?[]const u8 {
    if (view.parents > 1) return "merge commit";
    if (!view.signed) return "unsigned commit";
    return validateStrict(view.subject);
}

fn validateCore(subject: []const u8) ?[]const u8 {
    if (subject.len > max_subject_bytes) return "subject too long";
    const open = std.mem.findScalar(u8, subject, '(') orelse return "missing (<scope>)";
    const kind = subject[0..open];
    var known = false;
    for (types) |t| {
        if (std.mem.eql(u8, t, kind)) known = true;
    }
    if (!known) return "unknown type";
    const close = std.mem.findScalarPos(u8, subject, open, ')') orelse return "unclosed scope";
    const scope = subject[open + 1 .. close];
    if (scope.len == 0) return "empty scope";
    for (scope) |c| {
        const ok = std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '-' or c == '/' or c == '_';
        if (!ok) return "scope must be lowercase [a-z0-9-/_]";
    }
    if (!std.mem.startsWith(u8, subject[close + 1 ..], ": ")) return "missing ': ' after scope";
    if (subject.len <= close + 3) return "empty summary";
    return null;
}

test "commit subjects" {
    const valid = validate("feat(trust): implement root rotation");
    try std.testing.expectEqual(@as(?[]const u8, null), valid);
    try std.testing.expect(validate("Initial commit") != null);
    try std.testing.expect(validate("feat: missing scope") != null);
    try std.testing.expect(validate("wip(core): x") != null);
    try std.testing.expect(validate("fix(Core): x") != null);
}

test "fixup prefixes and the revert type" {
    try std.testing.expect(validate("fixup! feat(repo): add hooks") == null);
    try std.testing.expect(validate("squash! fix(core): keep the pointer") == null);
    try std.testing.expect(validate("amend! docs(repo): describe hooks") == null);
    try std.testing.expect(validate("fixup! wip") != null);
    try std.testing.expect(validate("revert(trust): revert root rotation") == null);
    try std.testing.expect(acceptMessage("fixup! feat(repo): add hooks\n") == null);
}

test "message files skip comments, empty text, and merges" {
    try std.testing.expect(acceptMessage("feat(repo): add hooks\n\nbody\n") == null);
    try std.testing.expect(acceptMessage("\n# comment\n") == null);
    try std.testing.expect(acceptMessage("Merge branch 'main'\n") == null);
    try std.testing.expect(acceptMessage("# note\n\nfix: no scope\n") != null);
    try std.testing.expectEqualStrings(
        "merge commit",
        acceptMode("Merge branch 'main'\n", true).?,
    );
    try std.testing.expectEqualStrings(
        "fixup subject",
        acceptMode("fixup! feat(repo): add hooks\n", true).?,
    );
}

test "strict mode reads signature headers" {
    const unsigned = try inspectCommit("tree abc\nparent def\n\nfeat(repo): ok\n");
    try std.testing.expectEqualStrings("unsigned commit", strictReason(unsigned).?);
    const fixup = try inspectCommit(
        "tree abc\nparent def\ngpgsig -----BEGIN-----\n -----END-----\n\nfixup! feat(repo): ok\n",
    );
    try std.testing.expect(fixup.signed);
    try std.testing.expectEqualStrings("fixup subject", strictReason(fixup).?);
    const merge = try inspectCommit(
        "tree abc\nparent a\nparent b\ngpgsig x\n\nMerge branch 't'\n",
    );
    try std.testing.expectEqualStrings("merge commit", strictReason(merge).?);
    const ok = try inspectCommit(
        "tree abc\nparent def\ngpgsig-sha256 x\n\nrevert(repo): revert hooks\n",
    );
    try std.testing.expect(strictReason(ok) == null);
    try std.testing.expectError(error.BadCommit, inspectCommit("no blank line"));
}

test "strict flag is independent of the range" {
    const parsed = try parseArgs(&.{ "check-commits", "--strict", "a..b" });
    try std.testing.expect(parsed.strict);
    try std.testing.expectEqualStrings("a..b", parsed.range);
    const file = try parseArgs(&.{ "check-commits", "--message-file", "m" });
    try std.testing.expectEqualStrings("m", file.message_file.?);
    try std.testing.expect(!file.strict);
    try std.testing.expectError(error.Usage, parseArgs(&.{ "check-commits", "--message-file" }));
}
