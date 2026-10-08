//! Build-tool ZIP extraction reuses the bounded std.zip approach in tools/evidence/ingest.zig.
const std = @import("std");
const root = @import("main.zig");

pub fn extract(
    gpa: std.mem.Allocator,
    io: std.Io,
    out: std.Io.Dir,
    bytes: []const u8,
    source: root.Source,
) !void {
    // SAFETY: Io.random fills the entire array before use.
    var nonce: [8]u8 = undefined;
    io.random(&nonce);
    // SAFETY: bufPrint writes the returned initialized slice.
    var name: [64]u8 = undefined;
    const temporary = try std.fmt.bufPrint(&name, ".source-{s}.zip", .{
        std.fmt.bytesToHex(nonce, .lower),
    });
    const archive = try out.createFile(io, temporary, .{ .exclusive = true, .read = true });
    defer out.deleteFile(io, temporary) catch |err| std.log.err("ZIP cleanup: {t}", .{err});
    defer archive.close(io);
    try archive.writeStreamingAll(io, bytes);
    // SAFETY: Reader writes the initialized prefix before it is observed.
    var buffer: [4096]u8 = undefined;
    var reader = archive.reader(io, &buffer);
    var iterator = try std.zip.Iterator.init(&reader);
    if (iterator.cd_record_count > 65_536) return error.FetchTooLarge;
    var total: u64 = 0;
    var kept: u32 = 0;
    while (try iterator.next()) |entry| {
        total = std.math.add(u64, total, entry.uncompressed_size) catch return error.FetchTooLarge;
        if (total > 512 << 20 or entry.uncompressed_size > 64 << 20) return error.FetchTooLarge;
        // SAFETY: Reader writes the initialized prefix before it is observed.
        var path_buffer: [4096]u8 = undefined;
        const raw_path = try entry.getFilename(&reader, &path_buffer, .{});
        const path = root.strip(raw_path, source.strip_components) orelse continue;
        if (!root.selected(path, source.extract)) continue;
        if (std.mem.endsWith(u8, path, "/")) continue;
        if (!root.safe(path)) return error.FetchUnsafePath;
        try reader.seekTo(entry.header_zip_offset);
        const header = try reader.interface.takeStruct(std.zip.CentralDirectoryFileHeader, .little);
        const kind = (header.external_file_attributes >> 16) & 0o170000;
        if (kind != 0 and kind != 0o100000) return error.FetchUnsupportedLink;
        const size = std.math.cast(usize, entry.uncompressed_size) orelse
            return error.FetchTooLarge;
        const data = try gpa.alloc(u8, size);
        defer gpa.free(data);
        var writer: std.Io.Writer = .fixed(data);
        try entry.extractTo(&reader, &writer);
        if (writer.end != data.len or std.hash.Crc32.hash(data) != entry.crc32)
            return error.FetchInvalidArchive;
        if (std.fs.path.dirname(path)) |parent| try out.createDirPath(io, parent);
        const permissions: std.Io.File.Permissions = if (root.selected(path, source.executables))
            .executable_file
        else
            .default_file;
        const file = try out.createFile(io, path, .{ .permissions = permissions });
        defer file.close(io);
        try file.writeStreamingAll(io, data);
        kept += 1;
    }
    if (kept == 0) return error.FetchNothingExtracted;
}

test "build tool ZIP accepts selected regular data and rejects symlinks" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source: root.Source = .{
        .url = "https://example.com/tool",
        .sha256 = "unused",
        .strip_components = 1,
        .extract = &.{"tool.exe"},
    };
    try extract(
        std.testing.allocator,
        std.testing.io,
        tmp.dir,
        @embedFile("fixtures/tool.zip"),
        source,
    );
    try std.testing.expectError(
        error.FetchUnsupportedLink,
        extract(
            std.testing.allocator,
            std.testing.io,
            tmp.dir,
            @embedFile("fixtures/link.zip"),
            source,
        ),
    );
}
