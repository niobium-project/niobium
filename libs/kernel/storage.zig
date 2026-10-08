//! Descriptor-relative owned storage. No recursive deletion or symlink-following writes.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const access = @import("access");
const platform = @import("platform");
const t = @import("types.zig");
const wire = @import("wire.zig");
const Error = t.Error;
const Dir = std.Io.Dir;
pub const metadata = ".niobium-v2";

pub const Store = struct {
    io: std.Io,
    arena: std.mem.Allocator,
    binding: t.RootBinding,
    dir: Dir,
    lock: ?std.Io.File = null,

    pub fn open(options: t.Options, binding: t.RootBinding) Error!Store {
        const parent_path = std.fs.path.dirname(binding.path) orelse return error.KernelInvalid;
        const parent = Dir.cwd().openDir(options.io, parent_path, .{}) catch |err|
            return platform.api.mapFs(err);
        defer parent.close(options.io);
        const leaf = std.fs.path.basename(binding.path);
        var created_root = false;
        const dir = parent.openDir(
            options.io,
            leaf,
            .{
                .follow_symlinks = false,
                .iterate = true,
            },
        ) catch |err| switch (err) {
            error.FileNotFound => made: {
                const made = try access.createDirectory(options.arena, options.io, parent, leaf);
                created_root = true;
                break :made made.dir;
            },
            else => return platform.api.mapFs(err),
        };
        errdefer dir.close(options.io);
        if (created_root) try sync(options.io, parent);
        const observation = try access.inspect(
            options.arena,
            options.io,
            access.directoryFile(
                dir,
            ),
        );
        if (!observation.owner.equal(try access.currentOwner(options.io))) {
            return error.KernelOwnership;
        }
        const lock = dir.openFile(
            options.io,
            ".niobium-lock",
            .{
                .mode = .read_write,
                .follow_symlinks = false,
            },
        ) catch |err| switch (err) {
            error.FileNotFound => (try access.createFile(
                options.arena,
                options.io,
                dir,
                ".niobium-lock",
            )).file,
            else => return platform.api.mapFs(err),
        };
        errdefer lock.close(options.io);
        const lock_state = try access.inspect(options.arena, options.io, lock);
        if (!lock_state.owner.equal(observation.owner)) return error.KernelOwnership;
        if (!(lock.tryLock(options.io, .exclusive) catch |err| return platform.api.mapFs(err))) {
            return error.KernelBusy;
        }
        return .{
            .io = options.io,
            .arena = options.arena,
            .binding = binding,
            .dir = dir,
            .lock = lock,
        };
    }

    pub fn close(self: Store) void {
        if (self.lock) |lock| lock.close(self.io);
        self.dir.close(self.io);
    }

    pub fn read(self: Store, path: []const u8, max: u32) Error!?[]const u8 {
        const parent = self.openParent(path, false) catch |err| switch (err) {
            error.FsNotFound => return null,
            else => return err,
        };
        defer parent.close(self.io);
        const file = parent.dir.openFile(self.io, parent.name, .{
            .follow_symlinks = false,
        }) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return platform.api.mapFs(err),
        };
        defer file.close(self.io);
        const stat = file.stat(self.io) catch |err| return platform.api.mapFs(err);
        if (stat.kind != .file or stat.nlink != 1) return error.KernelOwnership;
        if (stat.size > max) return error.KernelLimit;
        const size = std.math.cast(usize, stat.size) orelse return error.KernelLimit;
        const bytes = try self.arena.alloc(u8, size);
        const count = file.readPositionalAll(self.io, bytes, 0) catch |err|
            return platform.api.mapFs(err);
        if (count != size) return error.FsIo;
        return bytes;
    }

    pub fn write(self: Store, path: []const u8, bytes: []const u8) Error!void {
        const parent = try self.openParent(path, true);
        defer parent.close(self.io);
        const name = try self.arena.print(".pending-{s}", .{try nonce(self.arena, self.io)});
        const created = try access.createFile(self.arena, self.io, parent.dir, name);
        defer created.file.close(self.io);
        created.file.writeStreamingAll(self.io, bytes) catch |err| return platform.api.mapFs(err);
        created.file.sync(self.io) catch |err| return platform.api.mapFs(err);
        Dir.rename(parent.dir, name, parent.dir, parent.name, self.io) catch |err|
            return platform.api.mapFs(err);
        try sync(self.io, parent.dir);
    }

    pub fn remove(self: Store, path: []const u8) Error!void {
        const parent = self.openParent(path, false) catch |err| switch (err) {
            error.FsNotFound => return,
            else => return err,
        };
        defer parent.close(self.io);
        parent.dir.deleteFile(self.io, parent.name) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return platform.api.mapFs(err),
        };
        try sync(self.io, parent.dir);
    }

    pub fn removeEmpty(self: Store, path: []const u8) Error!void {
        const parent = self.openParent(path, false) catch |err| switch (err) {
            error.FsNotFound => return,
            else => return err,
        };
        defer parent.close(self.io);
        parent.dir.deleteDir(self.io, parent.name) catch |err| switch (err) {
            error.FileNotFound, error.DirNotEmpty => return,
            else => return platform.api.mapFs(err),
        };
        try sync(self.io, parent.dir);
    }

    pub fn createDir(self: Store, path: []const u8) Error!Dir {
        const parent = try self.openParent(path, true);
        defer parent.close(self.io);
        const created = try access.createDirectory(self.arena, self.io, parent.dir, parent.name);
        errdefer created.dir.close(self.io);
        try sync(self.io, parent.dir);
        return created.dir;
    }

    pub fn openFile(self: Store, path: []const u8) Error!std.Io.File {
        const parent = try self.openParent(path, false);
        defer parent.close(self.io);
        const file = parent.dir.openFile(self.io, parent.name, .{
            .follow_symlinks = false,
        }) catch |err| return platform.api.mapFs(err);
        errdefer file.close(self.io);
        const stat = file.stat(self.io) catch |err| return platform.api.mapFs(err);
        if (stat.kind != .file or stat.nlink != 1) return error.KernelOwnership;
        return file;
    }

    pub fn exists(self: Store, path: []const u8) Error!bool {
        const parent = self.openParent(path, false) catch |err| switch (err) {
            error.FsNotFound => return false,
            else => return err,
        };
        defer parent.close(self.io);
        const stat = parent.dir.statFile(self.io, parent.name, .{
            .follow_symlinks = false,
        }) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return platform.api.mapFs(err),
        };
        return stat.kind != .unknown;
    }

    pub const Parent = struct {
        dir: Dir,
        owned: bool,
        name: []const u8,
        pub fn close(self: Parent, io: std.Io) void {
            if (self.owned) self.dir.close(io);
        }
    };

    pub fn openParent(self: Store, path: []const u8, create: bool) Error!Parent {
        try wire.path(path);
        var result: Parent = .{ .dir = self.dir, .owned = false, .name = path };
        errdefer result.close(self.io);
        var parts = std.mem.splitScalar(u8, path, '/');
        var part = parts.next() orelse return error.KernelInvalid;
        while (parts.next()) |next| {
            const dir = result.dir.openDir(self.io, part, .{
                .follow_symlinks = false,
            }) catch |err| switch (err) {
                error.FileNotFound => if (create) made: {
                    const made = try access.createDirectory(self.arena, self.io, result.dir, part);
                    try sync(self.io, result.dir);
                    break :made made.dir;
                } else return error.FsNotFound,
                else => return platform.api.mapFs(err),
            };
            result.close(self.io);
            result = .{ .dir = dir, .owned = true, .name = next };
            part = next;
        }
        result.name = part;
        return result;
    }
};

pub fn sync(io: std.Io, dir: Dir) Error!void {
    try access.syncDirectory(io, dir);
}

pub fn nonce(arena: std.mem.Allocator, io: std.Io) Error![]const u8 {
    var bytes: [16]u8 = undefined; // SAFETY: random fills every byte.
    io.random(&bytes);
    return arena.dupe(u8, &std.fmt.bytesToHex(bytes, .lower));
}
