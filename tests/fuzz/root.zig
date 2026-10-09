//! `zig build test:fuzz` replays the corpus. Add `-Dcontinuous-fuzz --fuzz` to fuzz.
//! Corpus seeds live in tests/fuzz/corpus/<target>/.

const std = @import("std");
const contracts = @import("contracts");
const package = @import("package");
const program = @import("program");
const content = @import("content");
const image = @import("image");

test "fuzz tar header and pax parsing" {
    try std.testing.fuzz({}, fuzzTar, .{ .corpus = &.{ "", "13 path=a/bc\n", "ustar\x0000" } });
}

fn fuzzTar(_: void, smith: *std.testing.Smith) anyerror!void {
    var block: [package.tar.block_len]u8 = @splat(0);
    _ = smith.slice(&block); // lint-allow(no-discard-call): the length is irrelevant for a block.
    if (package.tar.parseHeader(&block)) |header| {
        try std.testing.expect(header.name.len <= 100);
        try std.testing.expect(header.prefix.len <= 155);
    } else |_| {}
    if (package.tar.parsePax(&block)) |pax| {
        if (pax.path) |p| try std.testing.expect(p.len < block.len);
    } else |_| {}
}

test "fuzz strict extraction never escapes staging" {
    try std.testing.fuzz({}, fuzzExtract, .{ .corpus = &.{ "", "component.json" } });
}

fn fuzzExtract(_: void, smith: *std.testing.Smith) anyerror!void {
    var payload: [4096]u8 = @splat(0);
    const len = smith.slice(&payload);
    const gpa = std.testing.allocator;
    const framed = try package.fixture.zstdRaw(gpa, payload[0..len]);
    defer gpa.free(framed);
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const io = std.testing.io;
    try tmp.dir.createDirPath(io, "staging");
    const staging = try tmp.dir.openDir(io, "staging", .{});
    defer staging.close(io);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var input: std.Io.Reader = .fixed(framed);
    const options: package.Options = .{ .compressed_len = framed.len };
    if (package.extract(gpa, arena.allocator(), io, &input, staging, options)) |_| {} else |_| {}
    var it = tmp.dir.iterate();
    while (try it.next(io)) |entry| try std.testing.expectEqualStrings("staging", entry.name);
}

test "N2-SAFE-02: product and native image parsers share bounded malformed-input replay" {
    try std.testing.fuzz({}, fuzzProduct, .{ .corpus = &.{
        "{}", "{\"schema\":2}", "NIOIMG02", "NIOTMP02", "\x7fELF", "MZ", "[[[[[[",
        "{\"id\":\"fuzz.product\",\"release_sequence\":1,\"target\":\"x86_64-linux\"," ++
            "\"profile\":{\"id\":\"fuzz.runtime\",\"target\":\"x86_64-linux\",\"primitives\":[]}}",
    } });
}

fn fuzzProduct(_: void, smith: *std.testing.Smith) anyerror!void {
    var buffer: [4096]u8 = @splat(0);
    const length = smith.slice(&buffer);
    const bytes = buffer[0..length];
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (program.model.decode(a, bytes)) |model| {
        const encoded = try program.model.encode(a, model);
        const roundtrip = try program.model.decode(a, encoded);
        try std.testing.expectEqualStrings(model.id, roundtrip.id);
    } else |_| {}
    if (image.inspect(a, std.testing.io, .{ .bytes = bytes }, .{})) |descriptor| {
        try std.testing.expect(try descriptor.payload.end() <= bytes.len);
    } else |_| {}
    if (bytes.len == image.descriptor.size) {
        if (image.descriptor.decode(bytes[0..image.descriptor.size])) |descriptor| {
            const encoded = image.descriptor.encode(descriptor);
            try std.testing.expectEqualSlices(u8, bytes, &encoded);
        } else |_| {}
    }
}

test "N2-SAFE-02: canonical content accepts bounded trees or refuses without extraction" {
    try std.testing.fuzz({}, fuzzContent, .{ .corpus = &.{
        "", "13 path=../x\n", "ustar\x0000",
    } });
}

fn fuzzContent(_: void, smith: *std.testing.Smith) anyerror!void {
    var buffer: [4096]u8 = @splat(0);
    const length = smith.slice(&buffer);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const limits: contracts.Limits = .{
        .files_per_artifact = 64,
        .expanded_bytes = 1 << 20,
        .archive_entry_bytes = 1 << 20,
    };
    if (content.parseTar(a, std.testing.io, .{ .bytes = buffer[0..length] }, limits)) |tree| {
        try std.testing.expect(tree.entries.len <= limits.files_per_artifact);
        for (tree.entries) |entry| try content.names.check(entry.path, limits);
        var scratch: [4096]u8 = undefined; // SAFETY: discard writer owns its scratch buffer.
        var sink: std.Io.Writer.Discarding = .init(&scratch);
        const identity = try content.writeTar(a, std.testing.io, tree, &sink.writer, limits);
        try std.testing.expect(identity.bytes >= 1024);
    } else |_| {}
}
