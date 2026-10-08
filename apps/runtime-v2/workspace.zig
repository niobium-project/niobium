//! Private bootstrap storage exists before any product-controlled root is interpreted.
const std = @import("std");
const access = @import("access");
pub const Workspace = struct {
    parent: std.Io.Dir,
    directory: std.Io.Dir,
    name: []const u8,

    pub fn create(arena: std.mem.Allocator, io: std.Io, temporary: []const u8) !Workspace {
        if (!std.fs.path.isAbsolute(temporary)) return error.TemporaryDirectoryInvalid;
        const parent = try std.Io.Dir.cwd().openDir(io, temporary, .{});
        errdefer parent.close(io);
        var nonce: [16]u8 = undefined; // SAFETY: random fills the directory suffix.
        io.random(&nonce);
        const name = try arena.print("niobium-image-{s}", .{std.fmt.bytesToHex(nonce, .lower)});
        const created = try access.createDirectory(arena, io, parent, name);
        return .{ .parent = parent, .directory = created.dir, .name = name };
    }

    pub fn deinit(self: Workspace, io: std.Io) void {
        self.directory.close(io);
        self.parent.deleteTree(io, self.name) catch |err|
            std.log.warn("bootstrap snapshot cleanup: {s}", .{@errorName(err)});
        self.parent.close(io);
    }
};
