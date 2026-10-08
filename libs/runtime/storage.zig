//! User-scope managed storage. Relative paths are walked through no-follow directory handles;
//! atomic file replacement and directory synchronization precede durable state transitions.

const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const platform = @import("platform");

pub const Error = program.Error || platform.Error || error{ RootInvalid, RuntimeBusy };
const Dir = std.Io.Dir;

pub const Storage = struct {
    io: std.Io,
    arena: std.mem.Allocator,
    dir: Dir,
    path: []const u8,
    lock: std.Io.File,

    pub fn open(io: std.Io, arena: std.mem.Allocator, requested: []const u8) Error!Storage {
        if (!std.fs.path.isAbsolute(requested)) return error.RootInvalid;
        const leaf = std.fs.path.basename(requested);
        try program.validation.path(leaf);
        const parent = std.fs.path.dirname(requested) orelse return error.RootInvalid;
        const resolved = Dir.cwd().realPathFileAlloc(io, parent, arena) catch |err|
            return platform.api.mapFs(err);
        const path = try std.fs.path.join(arena, &.{ resolved, leaf });
        Dir.cwd().createDir(io, path, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return platform.api.mapFs(err),
        };
        const dir = Dir.cwd().openDir(io, path, .{
            .follow_symlinks = false,
            .iterate = true,
        }) catch |err|
            return platform.api.mapFs(err);
        errdefer dir.close(io);
        const lock = try acquireLock(io, dir);
        return .{ .io = io, .arena = arena, .dir = dir, .path = path, .lock = lock };
    }

    pub fn close(self: Storage) void {
        self.lock.close(self.io);
        self.dir.close(self.io);
    }

    pub fn unclaimedEmpty(self: Storage) Error!bool {
        var iterator = self.dir.iterate();
        for (0..2) |_| {
            const entry = iterator.next(self.io) catch |err| return platform.api.mapFs(err);
            const value = entry orelse return true;
            if (!std.mem.eql(u8, value.name, ".niobium-lock")) return false;
        }
        return false;
    }

    pub fn exists(self: Storage, path: []const u8) Error!bool {
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

    pub fn removeEmpty(self: Storage, path: []const u8) Error!void {
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

    pub fn createExclusiveDir(self: Storage, path: []const u8) Error!bool {
        const parent = try self.openParent(path, true);
        defer parent.close(self.io);
        parent.dir.createDir(self.io, parent.name, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => return false,
            else => return platform.api.mapFs(err),
        };
        try sync(self.io, parent.dir);
        return true;
    }

    pub fn read(self: Storage, path: []const u8, max: u32) Error!?[]const u8 {
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
        if (stat.kind != .file or stat.nlink != 1) return error.RootInvalid;
        if (stat.size > max) return error.ProgramLimit;
        const size = std.math.cast(usize, stat.size) orelse return error.ProgramLimit;
        const bytes = try self.arena.alloc(u8, size);
        const count = file.readPositionalAll(self.io, bytes, 0) catch |err|
            return platform.api.mapFs(err);
        if (count != size) return error.FsIo;
        return bytes;
    }

    pub fn write(self: Storage, path: []const u8, bytes: []const u8) Error!void {
        const parent = try self.openParent(path, true);
        defer parent.close(self.io);
        var atomic = parent.dir.createFileAtomic(self.io, parent.name, .{
            .replace = true,
        }) catch |err| return platform.api.mapFs(err);
        defer atomic.deinit(self.io);
        atomic.file.writeStreamingAll(self.io, bytes) catch |err| return platform.api.mapFs(err);
        atomic.file.sync(self.io) catch |err| return platform.api.mapFs(err);
        atomic.replace(self.io) catch |err| return platform.api.mapFs(err);
        try sync(self.io, parent.dir);
    }

    pub fn remove(self: Storage, path: []const u8) Error!void {
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

    pub fn pointer(self: Storage, generation: ?u64) Error!void {
        try self.remove("current.next");
        if (generation) |value| {
            const target = try self.arena.print("generations/{d}", .{value});
            self.dir.symLink(self.io, target, "current.next", .{
                .is_directory = true,
            }) catch |err| return platform.api.mapFs(err);
            Dir.rename(self.dir, "current.next", self.dir, "current", self.io) catch |err|
                return platform.api.mapFs(err);
            try sync(self.io, self.dir);
        } else try self.remove("current");
    }

    pub fn readPointer(self: Storage) Error!?[]const u8 {
        var buffer: [128]u8 = undefined; // SAFETY: readLink writes the returned prefix.
        const length = self.dir.readLink(self.io, "current", &buffer) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return platform.api.mapFs(err),
        };
        return try self.arena.dupe(u8, buffer[0..length]);
    }

    const Parent = struct {
        dir: Dir,
        owned: bool,
        name: []const u8,

        fn close(self: Parent, io: std.Io) void {
            if (self.owned) self.dir.close(io);
        }
    };

    fn openParent(self: Storage, path: []const u8, create: bool) Error!Parent {
        try program.validation.path(path);
        var result: Parent = .{ .dir = self.dir, .owned = false, .name = path };
        errdefer result.close(self.io);
        var parts = std.mem.splitScalar(u8, path, '/');
        var part = parts.next() orelse return error.ProgramPath;
        var depth: u16 = 0;
        while (parts.next()) |next| {
            depth += 1;
            if (depth > (contracts.Limits{}).path_components) return error.ProgramPath;
            if (create) result.dir.createDir(self.io, part, .default_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return platform.api.mapFs(err),
            };
            const dir = result.dir.openDir(self.io, part, .{
                .follow_symlinks = false,
            }) catch |err| return platform.api.mapFs(err);
            if (create) try sync(self.io, result.dir);
            result.close(self.io);
            result = .{ .dir = dir, .owned = true, .name = next };
            part = next;
        }
        result.name = part;
        return result;
    }
};

fn acquireLock(io: std.Io, dir: Dir) Error!std.Io.File {
    for (0..2) |_| {
        const file = dir.openFile(io, ".niobium-lock", .{
            .mode = .read_write,
            .follow_symlinks = false,
            .lock = .exclusive,
            .lock_nonblocking = true,
        }) catch |err| switch (err) {
            error.FileNotFound => dir.createFile(io, ".niobium-lock", .{
                .exclusive = true,
                .read = true,
                .lock = .exclusive,
                .lock_nonblocking = true,
            }) catch |creation| switch (creation) {
                error.PathAlreadyExists => continue,
                error.WouldBlock => return error.RuntimeBusy,
                else => return platform.api.mapFs(creation),
            },
            error.WouldBlock => return error.RuntimeBusy,
            else => return platform.api.mapFs(err),
        };
        errdefer file.close(io);
        const stat = file.stat(io) catch |err| return platform.api.mapFs(err);
        if (stat.kind != .file or stat.nlink != 1) return error.RootInvalid;
        return file;
    }
    return error.RuntimeBusy;
}

fn sync(io: std.Io, dir: Dir) Error!void {
    const file: std.Io.File = .{ .handle = dir.handle, .flags = .{ .nonblocking = false } };
    file.sync(io) catch |err| return platform.api.mapFs(err);
}
