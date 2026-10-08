//! Logical content, canonical identity, parser boundaries, and bounded streaming checks.

const std = @import("std");
const content = @import("root.zig");
const fixture = @import("tar").fixture;

test "N2-CONTENT-05 logical link kinds follow chains without rewriting readlink text" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const tree = try content.fromEntries(a, &.{
        .{ .path = "lib/tool", .body = .bytes("x") },
        .{ .path = "alias", .kind = .symlink, .link_target = "lib" },
        .{ .path = "nested", .kind = .symlink, .link_target = "alias/./tool" },
        .{ .path = "back", .kind = .symlink, .link_target = "lib/.." },
        .{ .path = "missing", .kind = .symlink, .link_target = "absent" },
    }, .{});
    const resolver = try content.names.LinkResolver.init(a, tree, .{});
    const file = try resolver.resolve("nested");
    try std.testing.expectEqual(.file, file.kind.?);
    try std.testing.expectEqualStrings("lib/tool", file.path);
    const root = try resolver.resolve("back");
    try std.testing.expectEqual(.directory, root.kind.?);
    try std.testing.expectEqualStrings("", root.path);
    try std.testing.expect((try resolver.resolve("missing")).kind == null);
    for (tree.entries) |entry| if (std.mem.eql(u8, entry.path, "nested")) {
        try std.testing.expectEqualStrings("alias/./tool", entry.link_target);
    };
}
const io = std.testing.io;

fn encoded(arena: std.mem.Allocator, entries: []const content.Entry) ![]const u8 {
    var writer: std.Io.Writer.Allocating = .init(arena);
    const identity = try content.writeTar(arena, io, .{ .entries = entries }, &writer.writer, .{});
    try std.testing.expectEqual(writer.written().len, identity.bytes);
    var hash: [32]u8 = undefined; // SAFETY: hash initializes the digest.
    std.crypto.hash.sha2.Sha256.hash(writer.written(), &hash, .{});
    try std.testing.expectEqualSlices(u8, &hash, &identity.sha256);
    return writer.written();
}

test "N2-CONTENT-01 canonical tree includes modes empty directories and UTF-8 symlinks" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entries = [_]content.Entry{
        .{ .path = "工具/run", .mode = 0o755, .body = .bytes("hello") },
        .{ .path = "empty", .kind = .directory, .mode = 0o750 },
        .{ .path = "bin/link", .kind = .symlink, .mode = 0o777, .link_target = "../工具/run" },
        .{ .path = "con:<>\\?", .body = .bytes("logical name") },
    };
    const bytes = try encoded(a, &entries);
    const tree = try content.parseTar(a, io, .{ .bytes = bytes }, .{});
    try std.testing.expectEqual(@as(usize, 6), tree.entries.len);
    try std.testing.expectEqualStrings("bin", tree.entries[0].path);
    try std.testing.expectEqualStrings("../工具/run", tree.entries[1].link_target);
    try std.testing.expectEqual(@as(u16, 0o750), tree.entries[3].mode);
    try std.testing.expectEqualSlices(u8, bytes, try encoded(a, tree.entries));
}

test "N2-CONTENT-01 canonical identity ignores source ordering owner and timestamps" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tar: fixture.Tar = .{ .gpa = a };
    try tar.file("b", "two");
    try tar.file("a", "one");
    try tar.end();
    @memcpy(tar.bytes.items[108..116], "0000123\x00");
    @memcpy(tar.bytes.items[136..148], "00001234567\x00");
    checksum(tar.bytes.items[0..512]);
    const tree = try content.parseTar(a, io, .{ .bytes = tar.bytes.items }, .{});
    const expected = try encoded(a, &.{
        .{ .path = "a", .body = .bytes("one") },
        .{ .path = "b", .body = .bytes("two") },
    });
    try std.testing.expectEqualSlices(u8, expected, try encoded(a, tree.entries));
}

fn checksum(block: []u8) void {
    @memset(block[148..156], ' ');
    var sum: u64 = 0;
    for (block) |byte| sum += byte;
    var index: usize = 154;
    block[index] = 0;
    while (index > 148) {
        index -= 1;
        block[index] = "01234567"[sum % 8];
        sum /= 8;
    }
}

fn rejectTar(bytes: []const u8, expected: content.Error) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(expected, content.parseTar(
        arena.allocator(),
        io,
        .{ .bytes = bytes },
        .{},
    ));
}

test "N2-CONTENT-02 parser rejects traversal special types duplicate and corrupt entries" {
    const a = std.testing.allocator;
    for ([_][]const u8{ "../escape", "/absolute", "a/../b", "a//b", "\xff" }) |name| {
        var tar: fixture.Tar = .{ .gpa = a };
        defer tar.deinit();
        try tar.file(name, "x");
        try tar.end();
        try rejectTar(tar.bytes.items, error.ContentInvalid);
    }
    for ([_]u8{ '1', '3', '4', '6', 'S', 'L', 'K' }) |kind| {
        var tar: fixture.Tar = .{ .gpa = a };
        defer tar.deinit();
        try tar.header(kind, "x", 0);
        try tar.end();
        try rejectTar(tar.bytes.items, error.ContentUnsupported);
    }
    var tar: fixture.Tar = .{ .gpa = a };
    defer tar.deinit();
    try tar.file("x", "1");
    try tar.file("x", "2");
    try tar.end();
    try rejectTar(tar.bytes.items, error.ContentConflict);
    tar.bytes.items[10] ^= 1;
    try rejectTar(tar.bytes.items, error.ContentInvalid);
}

test "N2-CONTENT-02 parser rejects malformed pax padding truncation and link escapes" {
    const a = std.testing.allocator;
    for ([_][]const u8{ "99 path=x\n", "10 path=x\n10 path=x\n", "20 GNU.sparse.size=1\n" }) |pax| {
        var tar: fixture.Tar = .{ .gpa = a };
        defer tar.deinit();
        try tar.pax(pax);
        try tar.file("x", "1");
        try tar.end();
        try rejectTar(tar.bytes.items, error.ContentInvalid);
    }
    var tar: fixture.Tar = .{ .gpa = a };
    defer tar.deinit();
    try tar.header('2', "link", 0);
    @memcpy(tar.bytes.items[157..166], "../escape");
    checksum(tar.bytes.items[0..512]);
    try tar.end();
    try rejectTar(tar.bytes.items, error.ContentInvalid);
    try rejectTar(tar.bytes.items[0..700], error.ContentInvalid);
}

test "N2-CONTENT-03 filter remap merge and generated snapshot reject conflicts" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const tree = try content.fromEntries(a, &.{
        .{ .path = "old/bin/tool", .body = .bytes("tool") },
        .{ .path = "old/link", .kind = .symlink, .mode = 0o777, .link_target = "bin/tool" },
        .{ .path = "other", .body = .bytes("skip") },
    }, .{});
    const mapped = try content.transform(a, tree, .{ .from = "old", .to = "new" }, .{});
    try std.testing.expectEqual(@as(usize, 4), mapped.entries.len);
    try std.testing.expectEqualStrings("bin/tool", mapped.entries[3].link_target);
    try std.testing.expectError(error.ContentConflict, content.merge(a, &.{ mapped, mapped }, .{}));
    try std.testing.expectError(error.ContentConflict, content.fromEntries(a, &.{
        .{ .path = "x", .body = .bytes("file") },
        .{ .path = "x/child", .body = .bytes("cannot nest under file") },
    }, .{}));
    var output: std.Io.Writer.Allocating = .init(a);
    const frozen = try content.freeze(io, .bytes("generated"), &output.writer, .{});
    try std.testing.expectEqual(@as(u64, 9), frozen.bytes);
    try std.testing.expectEqualStrings("generated", output.written());
}

fn allocationCase(gpa: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var buffer: [8 << 10]u8 = undefined; // SAFETY: only bytes written by writeTar are read.
    var writer: std.Io.Writer = .fixed(&buffer);
    const ref = try content.writeTar(a, io, .{ .entries = &.{
        .{ .path = "a/b", .body = .bytes("payload") },
        .{ .path = "a/link", .kind = .symlink, .mode = 0o777, .link_target = "./b" },
    } }, &writer, .{});
    const length = std.math.cast(usize, ref.bytes) orelse return error.ContentLimit;
    const bytes = buffer[0..length];
    const tree = try content.parseTar(a, io, .{ .bytes = bytes }, .{});
    const changed = try content.transform(a, tree, .{ .from = "a", .to = "b" }, .{});
    const combined = try content.merge(a, &.{ tree, changed }, .{});
    try std.testing.expectEqual(@as(usize, 6), combined.entries.len);
}

test "N2-CONTENT-01 symlink spelling remains part of content identity" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entries = [_]content.Entry{
        .{ .path = "lib/x", .body = .bytes("x") },
        .{ .path = "bin/x", .kind = .symlink, .mode = 0o777, .link_target = "../lib/./x" },
    };
    const first = try encoded(a, &entries);
    const tree = try content.parseTar(a, io, .{ .bytes = first }, .{});
    try std.testing.expectEqualStrings("../lib/./x", tree.entries[1].link_target);
    var alternative = entries;
    alternative[1].link_target = "../lib/x";
    const second = try encoded(a, &alternative);
    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "N2-CONTENT-02 symlink chains cannot escape through parent references or cycles" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(error.ContentInvalid, content.fromEntries(a, &.{
        .{ .path = "a", .kind = .symlink, .link_target = "." },
        .{ .path = "b", .kind = .symlink, .link_target = "a/.." },
    }, .{}));
    try std.testing.expectError(error.ContentInvalid, content.fromEntries(a, &.{
        .{ .path = "a", .kind = .symlink, .link_target = "b" },
        .{ .path = "b", .kind = .symlink, .link_target = "a" },
    }, .{}));
}

test "N2-CONTENT-02 all parser and transform allocation failures propagate" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

test "N2-CONTENT-04 file payload streams with metadata-only allocation" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const file = try temp.dir.createFile(io, "payload", .{ .read = true });
    defer file.close(io);
    const chunk: [64 << 10]u8 = @splat('x');
    for (0..32) |_| try file.writeStreamingAll(io, &chunk);
    var metadata: [32 << 10]u8 = undefined;
    var allocator: std.heap.FixedBufferAllocator = .init(&metadata);
    const source: content.Source = .{ .file = .{ .handle = file, .length = 2 << 20 } };
    const entries = [_]content.Entry{.{
        .path = "large",
        .body = .{ .source = source, .length = source.size() },
    }};
    var buffer: [1024]u8 = undefined;
    var discard: std.Io.Writer.Discarding = .init(&buffer);
    const identity = try content.writeTar(
        allocator.allocator(),
        io,
        .{ .entries = &entries },
        &discard.writer,
        .{},
    );
    try std.testing.expect(identity.bytes > 2 << 20);
    var tiny: [1]u8 = undefined;
    var failed: std.Io.Writer = .fixed(&tiny);
    try std.testing.expectError(error.ContentWriteFailed, content.freeze(
        io,
        .bytes("xx"),
        &failed,
        .{},
    ));
}

test "N2-CONTENT-02 count body pax mode and output limits are enforced" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tar: fixture.Tar = .{ .gpa = a };
    try tar.file("x", "large");
    try tar.end();
    const source: content.Source = .{ .bytes = tar.bytes.items };
    try std.testing.expectError(error.ContentLimit, content.parseTar(a, io, source, .{
        .archive_entry_bytes = 4,
    }));
    try std.testing.expectError(error.ContentLimit, content.parseTar(a, io, source, .{
        .expanded_bytes = 512,
    }));
    try std.testing.expectError(error.ContentLimit, content.fromEntries(a, &.{
        .{ .path = "a/b", .body = .bytes("x") },
    }, .{ .files_per_artifact = 1 }));
    try std.testing.expectError(error.ContentUnsupported, content.fromEntries(a, &.{
        .{ .path = "setuid", .mode = 0o4755 },
    }, .{}));
    try std.testing.expectError(error.ContentInvalid, content.fromEntries(a, &.{
        .{ .path = "bounds", .body = .{ .source = .{ .bytes = "x" }, .offset = 2 } },
    }, .{}));
    var pax: fixture.Tar = .{ .gpa = a };
    try pax.header('x', "pax", 65537);
    try pax.end();
    try std.testing.expectError(error.ContentLimit, content.parseTar(a, io, .{
        .bytes = pax.bytes.items,
    }, .{}));
    var buffer: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try std.testing.expectError(error.ContentLimit, content.writeTar(a, io, .{
        .entries = &.{.{ .path = "x", .body = .bytes("x") }},
    }, &writer, .{ .expanded_bytes = 512 }));
}

test "N2-CONTENT-04 borrowed file slices preserve base bounds and cancellation" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const file = try temp.dir.createFile(io, "source", .{ .read = true });
    defer file.close(io);
    try file.writeStreamingAll(io, "prefixdataTAIL");
    var source: content.Source = .{ .file = .{ .handle = file, .offset = 6, .length = 4 } };
    var bytes: [4]u8 = undefined; // SAFETY: read initializes every compared byte.
    try source.read(io, 0, &bytes);
    try std.testing.expectEqualStrings("data", &bytes);
    try std.testing.expectError(error.ContentInvalid, source.read(io, 1, &bytes));
    source.file.offset = std.math.maxInt(u64);
    try std.testing.expectError(error.ContentInvalid, source.read(io, 1, bytes[0..1]));
    var cancel: std.atomic.Value(bool) = .init(true);
    source.file.cancel = &cancel;
    try std.testing.expectError(error.Canceled, source.read(io, 0, bytes[0..1]));
}
