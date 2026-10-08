//! Private temporary state on the destination filesystem, shared by compiler adapters.

const std = @import("std");
const access = @import("access");
const content = @import("content");
const contracts = @import("contracts");

pub const Workspace = struct {
    io: std.Io,
    parent: std.Io.Dir,
    dir: std.Io.Dir,
    name: []const u8,
    output: []const u8,

    pub fn init(arena: std.mem.Allocator, io: std.Io, output: []const u8) !Workspace {
        const parent_path = std.fs.path.dirname(output) orelse ".";
        const parent = try std.Io.Dir.cwd().openDir(io, parent_path, .{});
        errdefer parent.close(io);
        var random: [16]u8 = undefined; // SAFETY: random fills the private workspace suffix.
        io.random(&random);
        const name = try arena.print(
            ".niobium-compiler-{s}",
            .{std.fmt.bytesToHex(random, .lower)},
        );
        const created = try access.createDirectory(arena, io, parent, name);
        return .{
            .io = io,
            .parent = parent,
            .dir = created.dir,
            .name = name,
            .output = std.fs.path.basename(output),
        };
    }

    pub fn deinit(self: Workspace) void {
        self.dir.close(self.io);
        self.parent.deleteTree(self.io, self.name) catch |err|
            std.log.warn("compiler cleanup: {s}", .{@errorName(err)});
        self.parent.close(self.io);
    }

    pub fn publish(self: Workspace, name: []const u8) !void {
        try self.dir.rename(name, self.parent, self.output, self.io);
    }
};

pub fn source(io: std.Io, file: std.Io.File) !content.Source {
    const stat = try file.stat(io);
    if (stat.kind != .file or stat.size > contracts.limits.default.native_image_bytes) {
        return error.InputInvalid;
    }
    return .{ .file = .{ .handle = file, .length = stat.size } };
}

pub fn digest(io: std.Io, input: content.Source, output: ?std.Io.File) !contracts.Digest {
    if (input.size() > contracts.limits.default.native_image_bytes) return error.InputLimit;
    var hash: std.crypto.hash.sha2.Sha256 = .init(.{});
    var scratch: [64 << 10]u8 = undefined; // SAFETY: positional read fills copied bytes.
    var offset: u64 = 0;
    while (offset < input.size()) {
        const count = std.math.cast(usize, @min(scratch.len, input.size() - offset)) orelse
            return error.InputLimit;
        try input.read(io, offset, scratch[0..count]);
        hash.update(scratch[0..count]);
        if (output) |file| try file.writeStreamingAll(io, scratch[0..count]);
        offset += count;
    }
    return hash.finalResult();
}
