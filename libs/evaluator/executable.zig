//! Pin the native worker to verified bytes, even if the original executable pathname is replaced.
const std = @import("std");
const contracts = @import("contracts");
const content = @import("content");
pub const Error = content.Error || error{ ExecutableIo, ExecutableChanged, ExecutableLimit };
pub const Input = struct { source: content.Source, sha256: contracts.Digest };
pub const Snapshot = struct {
    directory: std.Io.Dir,
    name: []const u8,
    path: []const u8,

    pub fn deinit(self: Snapshot, io: std.Io) void {
        self.directory.deleteFile(io, self.name) catch |err|
            std.log.warn("worker snapshot cleanup: {s}", .{@errorName(err)});
    }
};

pub fn hash(io: std.Io, source: content.Source) Error!contracts.Digest {
    return copy(io, source, null, null);
}

pub fn capture(
    arena: std.mem.Allocator,
    io: std.Io,
    workspace: std.Io.Dir,
    input: Input,
    cancel: ?*const std.atomic.Value(bool),
) Error!Snapshot {
    var nonce: [16]u8 = undefined; // SAFETY: random fills the private filename suffix.
    io.random(&nonce);
    const name = try arena.print("worker-{s}.exe", .{std.fmt.bytesToHex(nonce, .lower)});
    const file = workspace.createFile(io, name, .{
        .exclusive = true,
        .permissions = if (std.Io.File.Permissions.has_executable_bit)
            .fromMode(0o700)
        else
            .default_file,
    }) catch return error.ExecutableIo;
    errdefer workspace.deleteFile(io, name) catch |err|
        std.log.warn("failed worker snapshot cleanup: {s}", .{@errorName(err)});
    defer file.close(io);
    const actual = try copy(io, input.source, file, cancel);
    if (!std.mem.eql(u8, &actual, &input.sha256)) return error.ExecutableChanged;
    file.sync(io) catch return error.ExecutableIo;
    const path = workspace.realPathFileAlloc(io, name, arena) catch return error.ExecutableIo;
    return .{ .directory = workspace, .name = name, .path = path };
}

fn copy(
    io: std.Io,
    source: content.Source,
    output: ?std.Io.File,
    cancel: ?*const std.atomic.Value(bool),
) Error!contracts.Digest {
    if (source.size() == 0 or source.size() > contracts.limits.default.native_image_bytes)
        return error.ExecutableLimit;
    var digest: std.crypto.hash.sha2.Sha256 = .init(.{});
    var bytes: [64 << 10]u8 = undefined; // SAFETY: source read fills each consumed slice.
    var offset: u64 = 0;
    while (offset < source.size()) {
        if (cancel) |flag| if (flag.load(.acquire)) return error.Canceled;
        const count = std.math.cast(usize, @min(source.size() - offset, bytes.len)) orelse
            return error.ExecutableLimit;
        try source.read(io, offset, bytes[0..count]);
        digest.update(bytes[0..count]);
        if (output) |file| file.writePositionalAll(io, bytes[0..count], offset) catch
            return error.ExecutableIo;
        offset += count;
    }
    return digest.finalResult();
}

test "N2-EVAL-04: executable capture follows the verified file, not a replaced pathname" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const io = std.testing.io;
    try temp.dir.writeFile(io, .{ .sub_path = "original", .data = "trusted" });
    const original = try temp.dir.openFile(io, "original", .{});
    defer original.close(io);
    const source: content.Source = .{ .file = .{ .handle = original, .length = 7 } };
    const expected = try hash(io, source);
    try temp.dir.rename("original", temp.dir, "held", io);
    try temp.dir.writeFile(io, .{ .sub_path = "original", .data = "changed" });
    const snapshot = try capture(
        arena.allocator(),
        io,
        temp.dir,
        .{ .source = source, .sha256 = expected },
        null,
    );
    defer snapshot.deinit(io);
    const bytes = try temp.dir.readFileAlloc(io, snapshot.name, arena.allocator(), .limited(32));
    try std.testing.expectEqualStrings("trusted", bytes);
    try std.testing.expectError(
        error.ExecutableChanged,
        capture(
            arena.allocator(),
            io,
            temp.dir,
            .{ .source = .{ .bytes = "changed" }, .sha256 = expected },
            null,
        ),
    );
}
