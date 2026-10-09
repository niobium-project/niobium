//! Docs lint (zig build check:docs): relative links resolve, ADR fields, acceptance IDs, spec
//! filenames identify current owners without version suffixes. Docs use English and public hosts;
//! every
//! build target has a tier on the Platform support page.

const std = @import("std");
const repo = @import("repo");
const links = @import("links.zig");
const locales = @import("locales.zig");
const targets = @import("targets.zig");

pub const acceptance_path = "docs/acceptance-plan.md";

/// Public hosts the repository may reference; adding one is a reviewed change.
/// `example.com` and its subdomains are always allowed for fixtures.
pub const allowed_hosts = [_][]const u8{
    "127.0.0.1",
    "cdn.jsdelivr.net",
    "cmake.org",
    "developers.cloudflare.com",
    "developer.apple.com", // Primary macOS filesystem and signing API documentation.
    "awscli.amazonaws.com",
    "codecov.io",
    "codeload.github.com",
    "discourse.cmake.org",
    "docs.virustotal.com",
    "docs.wasmtime.dev", // Upstream Component C API and Pulley profile documentation.
    "github.com",
    "json-schema.org",
    "learn.microsoft.com", // Primary Windows native format and access contracts.
    "doc.rust-lang.org", // Primary native CRT linkage reference.
    "sourceware.org", // Primary GNU Binutils PE weak-alias compatibility fixes.
    "man7.org", // Linux man-pages ACL semantics.
    "niobium-project.dev",
    "niobium.dev",
    "nsis.sourceforge.io",
    "raw.githubusercontent.com",
    "go.dev", // Pinned Go toolchain archives (ADR-0027).
    "proxy.golang.org", // Public Go module acquisition for the build-time Starlark worker.
    "static.rust-lang.org", // Pinned Rust toolchain archives (ADR-0027).
    "registry.npmjs.org",
    "schemas.microsoft.com",
    "sourceforge.net",
    "support.apple.com", // Apple platform signing requirements.
    "www.apple.com",
    "www.gnu.org", // Primary tar reproducibility documentation.
    "www.freedesktop.org",
};

/// Text files scanned for URL hosts.
pub const text_suffixes = [_][]const u8{
    ".md",  ".mdx", ".zig",   ".zon", ".json", ".manifest", ".h", ".c", ".gitignore", ".yml",
    ".mjs", ".ts",  ".astro", ".go",  ".star",
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const files = try repo.list(arena, io);
    var report: repo.Report = .{ .arena = arena, .tool = "check-docs" };
    const adr_index = try repo.read(arena, io, "docs/adr/README.md");
    for (files.paths) |path| {
        const markdown = isMarkdown(path);
        if (!isText(path) and !markdown) continue;
        const bytes = try repo.read(arena, io, path);
        try checkHosts(&report, path, bytes);
        try checkLanguage(&report, io, path, bytes, markdown);
        if (!markdown) continue;
        try checkLinks(&report, io, path, bytes);
        if (isAdr(path)) try checkAdr(&report, path, bytes, adr_index);
        if (std.mem.startsWith(u8, path, "docs/spec/") and hasVersion(path)) {
            try report.add("{s}: spec filename must not end with a version suffix", .{path});
        }
    }
    try checkAcceptance(&report, io, files);
    try checkPlatforms(&report, io);
    try report.finish(io);
}

/// English only outside `locales.cjkAllowed`; the site's two locales mirror each other.
fn checkLanguage(
    report: *repo.Report,
    io: std.Io,
    path: []const u8,
    bytes: []const u8,
    markdown: bool,
) !void {
    if (locales.cjkChecked(path, markdown) and !locales.cjkAllowed(path)) {
        if (cjkLine(bytes)) |line| try report.add("{s}:{d}: must be English (ADR-0017)", .{
            path,
            line,
        });
    }
    const other = try locales.counterpart(report.arena, path) orelse return;
    if (repo.exists(io, other)) return;
    if (std.mem.startsWith(u8, path, locales.zh_content)) {
        try report.add("{s}: Chinese page has no English page at {s}", .{ path, other });
    } else {
        try report.add("{s}: English page has no Chinese translation at {s}", .{ path, other });
    }
}

/// Every build target has a tier on the Platform support page (ADR-0014).
fn checkPlatforms(report: *repo.Report, io: std.Io) !void {
    const source = try repo.read(report.arena, io, targets.targets_path);
    const page = try repo.read(report.arena, io, targets.platforms_page);
    switch (targets.check(source, page)) {
        .ok => {},
        .no_targets => try report.add("{s}: no `.name = \"...\"` target found", .{
            targets.targets_path,
        }),
        .missing => |name| try report.add("{s}: target `{s}` from {s} has no tier", .{
            targets.platforms_page,
            name,
            targets.targets_path,
        }),
    }
}

fn isAdr(path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, "docs/adr/")) return false;
    const name = path["docs/adr/".len..];
    return name.len > 5 and std.ascii.isDigit(name[0]) and name[4] == '-';
}

pub fn hasVersion(path: []const u8) bool {
    const stem = path[0 .. path.len - ".md".len];
    const dash = std.mem.findScalarLast(u8, stem, '-') orelse return false;
    const tail = stem[dash + 1 ..];
    if (tail.len < 2 or tail[0] != 'v') return false;
    for (tail[1..]) |c| {
        if (!std.ascii.isDigit(c) and c != '.') return false;
    }
    return true;
}

fn checkAdr(
    report: *repo.Report,
    path: []const u8,
    bytes: []const u8,
    index: []const u8,
) !void {
    const fields = [_][]const u8{ "Status", "Date" };
    for (fields) |field| {
        const marker = try report.arena.print("**{s}:**", .{field});
        if (std.mem.find(u8, bytes, marker) == null) try report.add(
            "{s}: ADR missing {s}",
            .{ path, field },
        );
    }
    const status = adrStatus(bytes) orelse {
        try report.add("{s}: ADR has an invalid status or missing successor", .{path});
        return;
    };
    const name = std.fs.path.basenamePosix(path);
    const marker = try report.arena.print("| [{s}]({s})", .{ name[0..4], name });
    const start = std.mem.find(u8, index, marker) orelse {
        try report.add("{s}: ADR missing from index", .{path});
        return;
    };
    const end = std.mem.findScalarPos(u8, index, start, '\n') orelse index.len;
    const expected = try report.arena.print("| {s}", .{status});
    if (std.mem.find(u8, index[start..end], expected) == null) {
        try report.add("{s}: ADR index status does not match {s}", .{ path, status });
    }
}

fn adrStatus(bytes: []const u8) ?[]const u8 {
    const marker = "- **Status:** ";
    const at = std.mem.find(u8, bytes, marker) orelse return null;
    const start = at + marker.len;
    const end = std.mem.findScalarPos(u8, bytes, start, '\n') orelse bytes.len;
    const status = std.mem.trim(u8, bytes[start..end], " \r");
    const values = [_][]const u8{ "Proposed", "Accepted", "Superseded", "Deprecated" };
    for (values) |value| {
        if (!std.mem.eql(u8, status, value)) continue;
        if (std.mem.eql(u8, value, "Superseded") and
            std.mem.find(u8, bytes, "**Superseded by:**") == null) return null;
        return status;
    }
    return null;
}

fn isText(path: []const u8) bool {
    for (text_suffixes) |suffix| {
        if (std.mem.endsWith(u8, path, suffix)) return true;
    }
    return false;
}

fn isMarkdown(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".md") or std.mem.endsWith(u8, path, ".mdx");
}

fn isLockfile(path: []const u8) bool {
    return std.mem.eql(u8, std.fs.path.basenamePosix(path), "package-lock.json");
}

fn checkHosts(report: *repo.Report, path: []const u8, bytes: []const u8) !void {
    const found = if (isLockfile(path)) forbiddenLockfileHost(bytes) else forbiddenHost(bytes);
    if (found) |host| try report.add(
        "{s}: URL host '{s}' is not in allowed_hosts",
        .{ path, host },
    );
}

/// Markdown links `](target)`, resolved by `links.classify`.
fn checkLinks(report: *repo.Report, io: std.Io, path: []const u8, bytes: []const u8) !void {
    var rest = bytes;
    while (std.mem.find(u8, rest, "](")) |start| {
        rest = rest[start + 2 ..];
        const end = std.mem.findAny(u8, rest, ") \n") orelse break;
        const target_raw = rest[0..end];
        rest = rest[end..];
        const found = switch (try links.classify(report.arena, path, target_raw)) {
            .skip => true,
            .file => |file| repo.exists(io, file),
            .route => |base| routeExists(io, try links.routeCandidates(report.arena, base)),
        };
        if (!found) try report.add("{s}: broken link '{s}'", .{ path, target_raw });
        if (locales.crossesLocale(path, target_raw)) try report.add(
            "{s}: link '{s}' leaves the page's locale",
            .{ path, target_raw },
        );
    }
}

fn routeExists(io: std.Io, candidates: [4][]const u8) bool {
    for (candidates) |candidate| {
        if (repo.exists(io, candidate)) return true;
    }
    return false;
}

pub const IdSet = std.StringArrayHashMapUnmanaged(void);

/// Collects complete legacy N1 and active N2 acceptance identifiers.
pub fn collectIds(arena: std.mem.Allocator, bytes: []const u8, set: *IdSet) !void {
    var index: usize = 0;
    while (std.mem.findScalarPos(u8, bytes, index, 'N')) |start| {
        index = start + 1;
        if (start + 4 > bytes.len or bytes[start + 2] != '-') continue;
        const legacy = bytes[start + 1] == '1';
        if (!legacy and bytes[start + 1] != '2') continue;
        if (start > 0 and std.ascii.isAlphanumeric(bytes[start - 1])) continue;
        var end = start + 3;
        while (end < bytes.len and
            (std.ascii.isAlphanumeric(bytes[end]) or bytes[end] == '-')) end += 1;
        if (end - start > 40 or end - start < 7) continue;
        if (bytes[end - 3] != '-' or !std.ascii.isDigit(bytes[end - 2]) or
            !std.ascii.isDigit(bytes[end - 1])) continue;
        const family = bytes[start + 3 .. end - 3];
        if (!validFamily(family)) continue;
        if (legacy and !std.mem.eql(u8, family, "UJ") and
            !std.mem.eql(u8, family, "INV") and !std.mem.eql(u8, family, "AC")) continue;
        try set.put(arena, bytes[start..end], {});
    }
}

fn validFamily(family: []const u8) bool {
    if (family.len == 0 or family.len > 32) return false;
    var parts = std.mem.splitScalar(u8, family, '-');
    while (parts.next()) |part| {
        if (part.len == 0 or !std.ascii.isUpper(part[0])) return false;
        for (part[1..]) |byte| {
            if (!std.ascii.isUpper(byte) and !std.ascii.isDigit(byte)) return false;
        }
    }
    return true;
}

/// One current ledger owns all active IDs and preserves each evidence scope.
fn checkAcceptance(report: *repo.Report, io: std.Io, files: repo.Files) !void {
    var planned: IdSet = .empty;
    var needs_test: IdSet = .empty;
    const plan = try repo.read(report.arena, io, acceptance_path);
    try collectPlan(report, acceptance_path, plan, &planned, &needs_test);
    var cited: IdSet = .empty;
    for (files.paths) |path| {
        if (!std.mem.endsWith(u8, path, ".zig")) continue;
        const bytes = try repo.read(report.arena, io, path);
        try collectTestIds(report.arena, bytes, &cited);
    }
    for (cited.keys()) |id| {
        if (!planned.contains(id)) try report.add("test cites unknown acceptance ID {s}", .{id});
    }
    for (needs_test.keys()) |id| {
        if (!cited.contains(id)) try report.add(
            "{s} has unit-test coverage but no test cites it",
            .{id},
        );
    }
}

fn collectPlan(
    report: *repo.Report,
    path: []const u8,
    bytes: []const u8,
    planned: *IdSet,
    needs_test: *IdSet,
) !void {
    var in_table = false;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "|")) in_table = false;
        if (std.mem.startsWith(u8, line, "| ID | Description | Coverage | Status |")) {
            in_table = true;
            continue;
        }
        if (!in_table or !std.mem.startsWith(u8, line, "| N")) continue;
        var cells = std.mem.splitScalar(u8, line, '|');
        const leading = cells.next();
        std.debug.assert(leading != null);
        const id = std.mem.trim(u8, cells.next() orelse "", " ");
        const description = cells.next() orelse "";
        if (description.len == 0) try report.add("{s}: missing ID description", .{path});
        const coverage = std.mem.trim(u8, cells.next() orelse "", " ");
        const status = std.mem.trim(u8, cells.next() orelse "", " ");
        const count = planned.count();
        try collectIds(report.arena, id, planned);
        if (planned.count() == count) {
            try report.add("{s}: duplicate/invalid ID {s}", .{ path, id });
        }
        if (!acceptanceStatus(status)) try report.add("{s}: invalid status {s}", .{ path, status });
        if (needsTest(coverage, status)) try collectIds(report.arena, id, needs_test);
        if (std.mem.startsWith(u8, id, "N2-") and std.mem.eql(u8, status, "PASS")) {
            if (std.mem.find(u8, line, ".evidence/") == null or
                std.mem.find(u8, line, "<UTC>") != null)
            {
                try report.add("{s}: {s} PASS needs a concrete evidence path", .{ path, id });
            }
        }
    }
}

fn acceptanceStatus(status: []const u8) bool {
    for ([_][]const u8{ "PASS", "FAIL", "BLOCKED", "NOT_RUN", "DEFERRED" }) |valid| {
        if (std.mem.eql(u8, status, valid)) return true;
    }
    return false;
}

fn needsTest(coverage: []const u8, status: []const u8) bool {
    if (std.mem.eql(u8, status, "DEFERRED")) return false;
    return std.mem.eql(u8, coverage, "zig test") or std.mem.eql(u8, coverage, "aot-test");
}

fn collectTestIds(arena: std.mem.Allocator, bytes: []const u8, set: *IdSet) !void {
    var rest = bytes;
    while (std.mem.find(u8, rest, "test \"N")) |start| {
        rest = rest[start + "test \"".len ..];
        const end = std.mem.findScalar(u8, rest, '"') orelse break;
        try collectIds(arena, rest[0..end], set);
        rest = rest[end..];
    }
}

test "collectIds finds all families" {
    var set: IdSet = .empty;
    defer set.deinit(std.testing.allocator);
    try collectIds(std.testing.allocator, "N1-UJ-01 and N1-INV-08, N1-AC-21, N1-XX-01", &set);
    try std.testing.expectEqual(@as(usize, 3), set.count());
}

/// Returns the 1-based line of the first CJK code point, or of invalid UTF-8.
pub fn cjkLine(bytes: []const u8) ?usize {
    var line: usize = 1;
    var index: usize = 0;
    while (index < bytes.len) {
        const len = std.unicode.utf8ByteSequenceLength(bytes[index]) catch return line;
        if (index + len > bytes.len) return line;
        const point = std.unicode.utf8Decode(bytes[index..][0..len]) catch return line;
        if (isCjk(point)) return line;
        if (point == '\n') line += 1;
        index += len;
    }
    return null;
}

fn isCjk(point: u21) bool {
    return (point >= 0x3000 and point <= 0x303F) or // CJK symbols and punctuation
        (point >= 0x3400 and point <= 0x9FFF) or // CJK ideographs
        (point >= 0xF900 and point <= 0xFAFF) or // compatibility ideographs
        (point >= 0xFF00 and point <= 0xFFEF) or // full-width forms
        (point >= 0x20000 and point <= 0x2FFFF); // supplementary ideographs
}

/// Returns the first URL host in `bytes` that is not on `allowed_hosts`.
pub fn forbiddenHost(bytes: []const u8) ?[]const u8 {
    var rest = bytes;
    while (std.mem.find(u8, rest, "://")) |start| {
        const scheme_ok = std.mem.endsWith(u8, rest[0..start], "http") or
            std.mem.endsWith(u8, rest[0..start], "https");
        rest = rest[start + 3 ..];
        if (!scheme_ok) continue;
        var end: usize = 0;
        while (end < rest.len and isHostByte(rest[end])) end += 1;
        // A URL that ends a sentence is followed by a period that is not part of the host.
        const host = std.mem.trimEnd(u8, rest[0..end], ".");
        // Empty hosts are scheme prefixes and format strings such as "http://{s}".
        if (host.len > 0 and !isAllowedHost(host)) return host;
    }
    return null;
}

/// npm lockfiles also carry upstream `funding` links; only `resolved` URLs say where packages
/// are downloaded from, which is where a private registry mirror would show up.
pub fn forbiddenLockfileHost(bytes: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.find(u8, line, "\"resolved\":") == null) continue;
        if (forbiddenHost(line)) |host| return host;
    }
    return null;
}

fn isHostByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '.' or c == '-';
}

fn isAllowedHost(host: []const u8) bool {
    if (std.mem.eql(u8, host, "example.com") or std.mem.endsWith(u8, host, ".example.com")) {
        return true;
    }
    for (allowed_hosts) |allowed| {
        if (std.mem.eql(u8, host, allowed)) return true;
    }
    return false;
}

test "cjk text is located by line" {
    try std.testing.expectEqual(@as(?usize, null), cjkLine("plain English -> ok, a <= b\n"));
    try std.testing.expectEqual(@as(?usize, 2), cjkLine("ok\n\xe4\xb8\xad\xe6\x96\x87\n"));
    try std.testing.expectEqual(@as(?usize, 1), cjkLine("full-width colon\xef\xbc\x9a"));
    try std.testing.expectEqual(@as(?usize, 3), cjkLine("a\nb\n\xff\n"));
}

test "only allowed url hosts" {
    try std.testing.expectEqual(@as(?[]const u8, null), forbiddenHost(
        "see https://github.com/niobium-project/niobium and http://127.0.0.1:8080/x",
    ));
    try std.testing.expectEqual(@as(?[]const u8, null), forbiddenHost("https://dl.example.com/a"));
    const placeholders = "\"https://\", \"http://{s}\"";
    try std.testing.expectEqual(@as(?[]const u8, null), forbiddenHost(placeholders));
    // Split so this file does not trip its own scan.
    try std.testing.expectEqualStrings("git.corp.internal", forbiddenHost(
        "clone https:" ++ "//git.corp.internal/team/repo.git",
    ).?);
    try std.testing.expectEqualStrings("mirror.example.net", forbiddenHost(
        "[m](http:" ++ "//mirror.example.net/)",
    ).?);
}

test {
    _ = links;
    _ = locales;
    _ = targets;
}

test "the user documentation site host is allowed" {
    try std.testing.expectEqual(@as(?[]const u8, null), forbiddenHost(
        "site: 'https://niobium-project.dev', see https://niobium-project.dev/start/",
    ));
}

test "a sentence-ending period is not part of the host" {
    try std.testing.expectEqual(@as(?[]const u8, null), forbiddenHost(
        "It is published at https://niobium-project.dev. Maintainer docs stay here.",
    ));
    // Split so this file does not trip its own scan.
    try std.testing.expectEqualStrings("git.corp.internal", forbiddenHost(
        "the mirror is https:" ++ "//git.corp.internal.",
    ).?);
}

test "npm lockfiles are checked by resolved URLs only" {
    // Split so this file does not trip its own scan.
    const lock = "\"node_modules/a\": {\n" ++
        "  \"resolved\": \"https://registry.npmjs.org/a/-/a-1.0.0.tgz\",\n" ++
        "  \"funding\": { \"url\": \"https:" ++ "//opencollective.com/a\" }\n";
    try std.testing.expectEqual(@as(?[]const u8, null), forbiddenLockfileHost(lock));
    const mirror = "  \"resolved\": \"https:" ++ "//npm.corp.internal/a/-/a-1.0.0.tgz\",\n";
    try std.testing.expectEqualStrings("npm.corp.internal", forbiddenLockfileHost(mirror).?);
    try std.testing.expect(isLockfile("apps/user-docs/package-lock.json"));
    try std.testing.expect(!isLockfile("apps/user-docs/package.json"));
}

test "site sources and workflows are scanned, mdx is markdown" {
    try std.testing.expect(isText(".github/workflows/user-docs.yml"));
    try std.testing.expect(isText("apps/user-docs/astro.config.mjs"));
    try std.testing.expect(isText("apps/user-docs/src/components/VersionSelect.astro"));
    try std.testing.expect(isText("apps/user-docs/src/content.config.ts"));
    try std.testing.expect(isMarkdown("apps/user-docs/src/content/docs/index.mdx"));
    try std.testing.expect(!isMarkdown("apps/user-docs/package.json"));
}

test "current spec filenames reject historical version suffixes" {
    try std.testing.expect(hasVersion("docs/spec/manifest-v1.md"));
    try std.testing.expect(!hasVersion("docs/spec/manifest.md"));
}

test "acceptance IDs include N2 and reject malformed suffixes" {
    var set: IdSet = .empty;
    defer set.deinit(std.testing.allocator);
    try collectIds(
        std.testing.allocator,
        "N1-UJ-01 N2-AUTH-01 N2-SAFE-01 N2-WSDK-01 N2-AUTH-010 N2--01 " ++
            "N2-CORE-E2E-01 N2-KERNEL-RECOVERY-01 N2-AUTH-01-extra N2-CORE--01",
        &set,
    );
    try std.testing.expectEqual(@as(usize, 6), set.count());
    try std.testing.expect(set.contains("N2-WSDK-01"));
}

test "deferred acceptance needs no fabricated test and status remains closed" {
    try std.testing.expect(!needsTest("zig test", "DEFERRED"));
    try std.testing.expect(needsTest("zig test", "NOT_RUN"));
    try std.testing.expect(needsTest("aot-test", "PASS"));
    try std.testing.expect(!acceptanceStatus("SUPPORTED"));
    try std.testing.expect(acceptanceStatus("BLOCKED"));
}

test "superseded ADRs name successors and reject unknown statuses" {
    try std.testing.expect(adrStatus("- **Status:** Superseded\n") == null);
    try std.testing.expect(adrStatus("- **Status:** Done\n") == null);
    try std.testing.expectEqualStrings("Accepted", adrStatus("- **Status:** Accepted\n").?);
    try std.testing.expectEqualStrings("Superseded", adrStatus(
        "- **Status:** Superseded\n- **Superseded by:** [new](0022.md)\n",
    ).?);
}

test "current acceptance ledger contains independent N1 and active N2 obligations" {
    var planned: IdSet = .empty;
    defer planned.deinit(std.testing.allocator);
    try collectIds(std.testing.allocator, "N1-AC-21 N2-CORE-01", &planned);
    try std.testing.expect(planned.contains("N1-AC-21"));
    try std.testing.expect(planned.contains("N2-CORE-01"));
    try std.testing.expectEqualStrings("docs/acceptance-plan.md", acceptance_path);
}
