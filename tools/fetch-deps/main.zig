//! `nb-fetch-deps --manifest third_party/deps.zon --package <name> --out <dir> [--cache <dir>]
//! [--patch <file>]...`: one third-party package into `out` (docs/adr/0011-third-party-fetch.md).
//! Every download is checked against its pinned sha256 and kept in `<cache>/<sha256>`, so a
//! package is fetched once per machine; later builds work offline. The cache defaults to
//! `$NIOBIUM_DEPS_CACHE`, else `niobium-deps` in Zig's global cache directory. Patches apply
//! strictly, in the order given. `zig build` runs this per package (build/steps/deps.zig) and
//! fails a step that writes to stderr, so only failures print.

const std = @import("std");
const patch = @import("patch.zig");
const archive_zip = @import("zip.zig");
const cache = @import("cache.zig");
const toolchain = @import("toolchain.zig");

const Dir = std.Io.Dir;
const max_download = 64 << 20;
const max_patch = 1 << 20;

pub const Archive = enum { none, tar_gz, zip };

pub const Source = struct {
    url: []const u8,
    sha256: []const u8,
    archive: Archive = .none,
    /// Leading path components removed from archive entries.
    strip_components: u32 = 0,
    /// Archive entries to keep: exact paths, or directories ending in `/`.
    extract: []const []const u8 = &.{},
    /// Destination of a plain file download.
    file: ?[]const u8 = null,
    max_download_bytes: u32 = max_download,
    /// Executable build tools only; runtime payload extraction has a separate contract.
    executables: []const []const u8 = &.{},
};

pub const Package = struct {
    name: []const u8,
    version: []const u8,
    sources: []const Source,
    patches: []const []const u8 = &.{},
};

pub const Manifest = struct { packages: []const Package };

const Args = struct {
    manifest: []const u8,
    package: []const u8,
    cache: ?[]const u8,
    out: []const u8,
    patches: []const []const u8,
};

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    const argv = try init.minimal.args.toSlice(arena);
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "toolchain")) {
        return toolchain.execute(init, argv);
    }
    const args = parseArgs(arena, argv) catch {
        std.debug.print("usage: nb-fetch-deps --manifest <deps.zon> --package <name> " ++
            "--out <dir> [--cache <dir>] [--patch <file>]...\n", .{});
        return 2;
    };
    const manifest = try loadManifest(io, arena, args.manifest);
    const package = for (manifest.packages) |p| {
        if (std.mem.eql(u8, p.name, args.package)) break p;
    } else {
        std.debug.print("fetch-deps: {s}: no package {s}\n", .{ args.manifest, args.package });
        return 1;
    };
    const cache_dir = args.cache orelse try cache.defaultCache(arena, init.environ_map);
    var out = try Dir.cwd().createDirPathOpen(io, args.out, .{});
    defer out.close(io);
    for (package.sources) |source| {
        const bytes = try obtain(io, init.gpa, arena, init.environ_map, cache_dir, source);
        switch (source.archive) {
            .none => try out.writeFile(io, .{ .sub_path = source.file.?, .data = bytes }),
            .tar_gz => try extract(io, out, bytes, source),
            .zip => try archive_zip.extract(init.gpa, io, out, bytes, source),
        }
    }
    for (args.patches) |path| try applyPatch(io, arena, out, path);
    return 0;
}

fn parseArgs(arena: std.mem.Allocator, argv: []const []const u8) !Args {
    var manifest: ?[]const u8 = null;
    var package: ?[]const u8 = null;
    var cache_dir: ?[]const u8 = null;
    var out: ?[]const u8 = null;
    var patches: std.ArrayList([]const u8) = .empty;
    var index: usize = 1;
    while (index + 1 < argv.len) : (index += 2) {
        const flag = argv[index];
        const value = argv[index + 1];
        if (std.mem.eql(u8, flag, "--manifest")) {
            manifest = value;
        } else if (std.mem.eql(u8, flag, "--package")) {
            package = value;
        } else if (std.mem.eql(u8, flag, "--cache")) {
            cache_dir = value;
        } else if (std.mem.eql(u8, flag, "--out")) {
            out = value;
        } else if (std.mem.eql(u8, flag, "--patch")) {
            try patches.append(arena, value);
        } else return error.UsageFetchDeps;
    }
    if (index != argv.len) return error.UsageFetchDeps;
    return .{
        .manifest = manifest orelse return error.UsageFetchDeps,
        .package = package orelse return error.UsageFetchDeps,
        .cache = cache_dir,
        .out = out orelse return error.UsageFetchDeps,
        .patches = patches.items,
    };
}

fn loadManifest(io: std.Io, arena: std.mem.Allocator, path: []const u8) !Manifest {
    const bytes = try Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 20));
    var diagnostics: std.zon.parse.Diagnostics = undefined; // SAFETY: filled by fromSlice.
    const manifest = std.zon.parse.fromSlice(Manifest, .{
        .gpa = arena,
        .arena = arena,
        .source = try arena.dupeSentinel(u8, bytes, 0),
        .diagnostics = &diagnostics,
    }) catch |err| {
        std.debug.print("fetch-deps: {f}\n", .{diagnostics.fmt(path)});
        return err;
    };
    if (manifest.packages.len > 64) return error.FetchInvalidLimit;
    for (manifest.packages) |package| {
        if (package.sources.len > 16) return error.FetchInvalidLimit;
        for (package.sources) |source| {
            const budget = try sourceBudget(source);
            std.debug.assert(budget != 0);
            if (source.sha256.len != 64) return error.FetchInvalidHash;
            for (source.sha256) |byte| {
                if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f'))
                    return error.FetchInvalidHash;
            }
            if (source.archive == .none) {
                const destination = source.file orelse return error.FetchUnsafePath;
                if (!safe(destination)) return error.FetchUnsafePath;
            }
        }
    }
    return manifest;
}

/// The verified bytes of `source`: from `cache/<sha256>` when present, else downloaded.
fn obtain(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    cache_path: []const u8,
    source: Source,
) ![]const u8 {
    return cache.obtain(
        io,
        gpa,
        arena,
        environ,
        cache_path,
        source.url,
        source.sha256,
        try sourceBudget(source),
    );
}

fn matches(bytes: []const u8, expected_hex: []const u8) bool {
    return cache.matches(bytes, expected_hex);
}

fn extract(io: std.Io, out: Dir, bytes: []const u8, source: Source) !void {
    var input: std.Io.Reader = .fixed(bytes);
    var window: [std.compress.flate.max_window_len]u8 = undefined; // SAFETY: inflate window.
    var inflate: std.compress.flate.Decompress = .init(&input, .gzip, &window);
    var name_buffer: [Dir.max_path_bytes]u8 = undefined; // SAFETY: tar entry names.
    var link_buffer: [Dir.max_path_bytes]u8 = undefined; // SAFETY: tar link names.
    var entries: std.tar.Iterator = .init(&inflate.reader, .{
        .file_name_buffer = &name_buffer,
        .link_name_buffer = &link_buffer,
    });
    var kept: usize = 0;
    var count: u32 = 0;
    var expanded: u64 = 0;
    while (try entries.next()) |entry| {
        count += 1;
        if (count > 65_536) return error.FetchTooLarge;
        expanded = std.math.add(u64, expanded, entry.size) catch return error.FetchTooLarge;
        if (expanded > 512 << 20) return error.FetchTooLarge;
        const path = strip(entry.name, source.strip_components) orelse continue;
        if (!selected(path, source.extract)) continue;
        if (entry.kind == .sym_link) return error.FetchUnsupportedLink;
        if (entry.kind != .file) continue;
        if (!safe(path)) return error.FetchUnsafePath;
        if (std.fs.path.dirname(path)) |parent| try out.createDirPath(io, parent);
        const permissions: std.Io.File.Permissions = if (selected(path, source.executables))
            .executable_file
        else
            .default_file;
        var file = try out.createFile(io, path, .{ .permissions = permissions });
        defer file.close(io);
        var buffer: [64 << 10]u8 = undefined; // SAFETY: writer scratch.
        var writer = file.writer(io, &buffer);
        try entries.streamRemaining(entry, &writer.interface);
        try writer.interface.flush();
        kept += 1;
    }
    if (kept == 0) return error.FetchNothingExtracted;
}

fn applyPatch(io: std.Io, arena: std.mem.Allocator, out: Dir, path: []const u8) !void {
    const text = try Dir.cwd().readFileAlloc(io, path, arena, .limited(max_patch));
    for (try patch.parse(arena, text)) |file| {
        if (!safe(file.path)) return error.FetchUnsafePath;
        const original = if (file.create) "" else try out.readFileAlloc(
            io,
            file.path,
            arena,
            .limited(max_download),
        );
        const patched = patch.apply(arena, original, file) catch |err| {
            std.debug.print("fetch-deps: {s}: {s}: {t}\n", .{ path, file.path, err });
            return err;
        };
        if (std.fs.path.dirname(file.path)) |parent| try out.createDirPath(io, parent);
        try out.writeFile(io, .{ .sub_path = file.path, .data = patched });
    }
}

/// `path` without its first `count` components; null when nothing is left.
pub fn strip(path: []const u8, count: u32) ?[]const u8 {
    var rest = path;
    for (0..count) |_| {
        const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
        rest = rest[slash + 1 ..];
    }
    return if (rest.len == 0) null else rest;
}

pub fn selected(path: []const u8, keep: []const []const u8) bool {
    for (keep) |entry| {
        if (std.mem.endsWith(u8, entry, "/")) {
            if (std.mem.startsWith(u8, path, entry)) return true;
        } else if (std.mem.eql(u8, path, entry)) return true;
    }
    return false;
}

pub fn safe(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or std.mem.indexOfScalar(u8, path, '\\') != null) {
        return false;
    }
    if (std.mem.indexOfScalar(u8, path, ':') != null) return false;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, "..") or std.mem.eql(u8, part, ".")) {
            return false;
        }
    }
    return true;
}

test {
    _ = patch;
    _ = archive_zip;
}

test "archive entry selection" {
    try std.testing.expectEqualStrings("lib/zstd.h", strip("zstd-1.5.7/lib/zstd.h", 1).?);
    try std.testing.expect(strip("zstd-1.5.7/", 1) == null);
    const keep = [_][]const u8{ "LICENSE", "lib/common/" };
    try std.testing.expect(selected("lib/common/xxhash.c", &keep));
    try std.testing.expect(selected("LICENSE", &keep));
    try std.testing.expect(!selected("LICENSE.md", &keep));
    try std.testing.expect(!selected("lib/decompress/x.c", &keep));
    try std.testing.expect(!safe("../x"));
    try std.testing.expect(!safe("a//b"));
    try std.testing.expect(!safe("C:/escape"));
    try std.testing.expect(!safe("tool.exe:stream"));
    try std.testing.expect(!safe("nul\x00name"));
    try std.testing.expect(safe("lib/common/x.c"));
}

test "the pinned sha256 is compared as lowercase hex" {
    try std.testing.expect(matches(
        "abc",
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    ));
    try std.testing.expect(!matches("abd", "ba7816bf"));
}

fn sourceBudget(source: Source) !u64 {
    if (source.max_download_bytes == 0 or source.max_download_bytes > 256 << 20) {
        return error.FetchInvalidLimit;
    }
    if (source.executables.len > 16) return error.FetchInvalidLimit;
    if (source.strip_components > 32 or source.extract.len > 64) return error.FetchInvalidLimit;
    for (source.executables) |path| {
        if (!safe(path)) return error.FetchUnsafePath;
        if (std.mem.endsWith(u8, path, "/")) return error.FetchUnsafePath;
    }
    return source.max_download_bytes;
}

fn boundedBody(reader: *std.Io.Reader, arena: std.mem.Allocator, max: u64) ![]u8 {
    return cache.boundedBody(reader, arena, max);
}

test "download rejects over-limit data before unbounded allocation" {
    const input: [4096]u8 = @splat('x');
    var storage: [512]u8 = undefined;
    var allocator = std.heap.FixedBufferAllocator.init(&storage);
    var reader: std.Io.Reader = .fixed(&input);
    try std.testing.expectError(
        error.FetchTooLarge,
        boundedBody(&reader, allocator.allocator(), 64),
    );
}

test "source download allowance has an explicit bounded range" {
    var source: Source = .{ .url = "https://example.com/source", .sha256 = "unused" };
    try std.testing.expectEqual(@as(u64, max_download), try sourceBudget(source));
    source.max_download_bytes = 128 << 20;
    try std.testing.expectEqual(@as(u64, 128 << 20), try sourceBudget(source));
    source.max_download_bytes = 0;
    try std.testing.expectError(error.FetchInvalidLimit, sourceBudget(source));
    source.max_download_bytes = (256 << 20) + 1;
    try std.testing.expectError(error.FetchInvalidLimit, sourceBudget(source));
}

test "build tool extraction uses explicit executable paths and rejects links and expansion" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source: Source = .{
        .url = "https://example.com/tool",
        .sha256 = "unused",
        .archive = .tar_gz,
        .strip_components = 1,
        .extract = &.{"tool"},
        .executables = &.{"tool"},
    };
    try extract(std.testing.io, tmp.dir, @embedFile("fixtures/tool.tar.gz"), source);
    const contents = try tmp.dir.readFileAlloc(
        std.testing.io,
        "tool",
        std.testing.allocator,
        .limited(32),
    );
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("abc", contents);
    if (std.Io.File.Permissions.has_executable_bit) {
        const stat = try tmp.dir.statFile(std.testing.io, "tool", .{});
        try std.testing.expect((stat.permissions.toMode() & 0o100) != 0);
    }
    try std.testing.expectError(
        error.FetchUnsupportedLink,
        extract(std.testing.io, tmp.dir, @embedFile("fixtures/link.tar.gz"), source),
    );
    try std.testing.expectError(
        error.FetchTooLarge,
        extract(std.testing.io, tmp.dir, @embedFile("fixtures/oversize.tar.gz"), source),
    );
}
