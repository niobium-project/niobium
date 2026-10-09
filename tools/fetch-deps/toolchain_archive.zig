//! Install one official archive into a tool prefix. Relative symlinks may use `..`
//! only when they remain inside that prefix. Hard links are copied after the scan.

const std = @import("std");
const layout = @import("toolchain_layout.zig");

const Dir = std.Io.Dir;
const max_entries: u32 = 65_536;
const max_expanded: u64 = 768 << 20;
const max_file: u64 = 256 << 20;
const max_links: usize = 8_192;

const Link = struct { from: []const u8, to: []const u8 };

pub fn installTarGz(
    arena: std.mem.Allocator,
    io: std.Io,
    out: Dir,
    bytes: []const u8,
    role: layout.Role,
) !void {
    var input: std.Io.Reader = .fixed(bytes);
    var window: [std.compress.flate.max_window_len]u8 = undefined; // SAFETY: inflate window.
    var inflate: std.compress.flate.Decompress = .init(&input, .gzip, &window);
    var name_buffer: [Dir.max_path_bytes]u8 = undefined; // SAFETY: tar entry names.
    var link_buffer: [Dir.max_path_bytes]u8 = undefined; // SAFETY: tar link names.
    var entries: std.tar.Iterator = .init(&inflate.reader, .{
        .file_name_buffer = &name_buffer,
        .link_name_buffer = &link_buffer,
    });
    var links: std.ArrayList(Link) = .empty;
    var count: u32 = 0;
    var expanded: u64 = 0;
    var kept: usize = 0;
    while (try entries.next()) |entry| {
        count += 1;
        if (count > max_entries) return error.FetchTooLarge;
        expanded = std.math.add(u64, expanded, entry.size) catch return error.FetchTooLarge;
        if (expanded > max_expanded or entry.size > max_file) return error.FetchTooLarge;
        const raw = layout.strip(entry.name, 1) orelse continue;
        if (entry.kind == .directory) continue;
        const path = try arena.dupe(u8, raw);
        if (!layout.safe(path)) return error.FetchUnsafePath;
        const dest = layout.destination(role, path) orelse continue;
        if (entry.kind == .sym_link) {
            try writeLink(arena, io, out, dest, entry.link_name);
            kept += 1;
            continue;
        }
        if (entry.kind != .file) {
            if (links.items.len == max_links) return error.FetchTooLarge;
            try links.append(arena, .{ .from = path, .to = try arena.dupe(u8, entry.link_name) });
            continue;
        }
        try writeFile(io, out, dest, &entries, entry);
        kept += 1;
    }
    try copyLinks(io, out, role, links.items);
    if (kept == 0 and links.items.len == 0) return error.FetchNothingExtracted;
}

pub fn installZip(
    gpa: std.mem.Allocator,
    io: std.Io,
    out: Dir,
    bytes: []const u8,
    role: layout.Role,
) !void {
    var nonce: [8]u8 = undefined; // SAFETY: random fills the suffix.
    io.random(&nonce);
    var name: [64]u8 = undefined; // SAFETY: bufPrint returns the initialized prefix.
    const temporary = try std.fmt.bufPrint(&name, ".source-{s}.zip", .{
        std.fmt.bytesToHex(nonce, .lower),
    });
    const archive = try out.createFile(io, temporary, .{ .exclusive = true, .read = true });
    defer out.deleteFile(io, temporary) catch |err| std.log.err("ZIP cleanup: {t}", .{err});
    defer archive.close(io);
    try archive.writeStreamingAll(io, bytes);
    var buffer: [4096]u8 = undefined; // SAFETY: reader fills the prefix it returns.
    var reader = archive.reader(io, &buffer);
    var iterator = try std.zip.Iterator.init(&reader);
    if (iterator.cd_record_count > max_entries) return error.FetchTooLarge;
    var total: u64 = 0;
    var kept: usize = 0;
    while (try iterator.next()) |entry| {
        const wrote = try writeZipEntry(gpa, io, out, role, &reader, entry, &total);
        if (wrote) kept += 1;
    }
    if (kept == 0) return error.FetchNothingExtracted;
}

fn writeFile(
    io: std.Io,
    out: Dir,
    dest: []const u8,
    entries: *std.tar.Iterator,
    entry: std.tar.Iterator.File,
) !void {
    if (std.fs.path.dirname(dest)) |parent| try out.createDirPath(io, parent);
    const permissions: std.Io.File.Permissions = if (layout.executable(dest))
        .executable_file
    else
        .default_file;
    var file = try out.createFile(io, dest, .{ .permissions = permissions });
    defer file.close(io);
    var buffer: [64 << 10]u8 = undefined; // SAFETY: writer scratch.
    var writer = file.writer(io, &buffer);
    try entries.streamRemaining(entry, &writer.interface);
    try writer.interface.flush();
}

fn writeLink(
    arena: std.mem.Allocator,
    io: std.Io,
    out: Dir,
    dest: []const u8,
    target: []const u8,
) !void {
    const link = try arena.dupe(u8, target);
    if (!layout.linkStaysInside(dest, link)) return error.FetchUnsafePath;
    if (std.fs.path.dirname(dest)) |parent| try out.createDirPath(io, parent);
    try out.symLink(io, link, dest, .{});
}

fn copyLinks(io: std.Io, out: Dir, role: layout.Role, links: []const Link) !void {
    for (links) |link| {
        const from = layout.strip(link.to, 1) orelse link.to;
        const source = layout.destination(role, from) orelse continue;
        const dest = layout.destination(role, link.from) orelse continue;
        if (!layout.safe(source) or !layout.safe(dest)) return error.FetchUnsafePath;
        if (std.fs.path.dirname(dest)) |parent| try out.createDirPath(io, parent);
        try Dir.copyFile(out, source, out, dest, io, .{});
    }
}

fn writeZipEntry(
    gpa: std.mem.Allocator,
    io: std.Io,
    out: Dir,
    role: layout.Role,
    reader: *std.Io.File.Reader,
    entry: std.zip.Iterator.Entry,
    total: *u64,
) !bool {
    total.* = std.math.add(u64, total.*, entry.uncompressed_size) catch return error.FetchTooLarge;
    if (total.* > max_expanded or entry.uncompressed_size > max_file) return error.FetchTooLarge;
    var path_buffer: [4096]u8 = undefined; // SAFETY: getFilename writes the returned prefix.
    const raw_path = try entry.getFilename(reader, &path_buffer, .{});
    const stripped = layout.strip(raw_path, 1) orelse return false;
    if (std.mem.endsWith(u8, stripped, "/")) return false;
    if (!layout.safe(stripped)) return error.FetchUnsafePath;
    const dest = layout.destination(role, stripped) orelse return false;
    try reader.seekTo(entry.header_zip_offset);
    const header = try reader.interface.takeStruct(std.zip.CentralDirectoryFileHeader, .little);
    const kind = (header.external_file_attributes >> 16) & 0o170000;
    if (kind != 0 and kind != 0o100000) return error.FetchUnsupportedLink;
    const size = std.math.cast(usize, entry.uncompressed_size) orelse return error.FetchTooLarge;
    const data = try gpa.alloc(u8, size);
    defer gpa.free(data);
    var writer: std.Io.Writer = .fixed(data);
    try entry.extractTo(reader, &writer);
    if (writer.end != data.len) return error.FetchInvalidArchive;
    if (std.hash.Crc32.hash(data) != entry.crc32) return error.FetchInvalidArchive;
    if (std.fs.path.dirname(dest)) |parent| try out.createDirPath(io, parent);
    const permissions: std.Io.File.Permissions = if (layout.executable(dest))
        .executable_file
    else
        .default_file;
    const file = try out.createFile(io, dest, .{ .permissions = permissions });
    defer file.close(io);
    try file.writeStreamingAll(io, data);
    return true;
}
