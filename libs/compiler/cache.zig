//! Local stage cache. Records reference verified immutable blobs; a damaged record is a miss.
const std = @import("std");
const contracts = @import("contracts");
const content = @import("content");
const lock = @import("lock.zig");
const program = @import("program");

pub const Error = lock.Error || content.Error || error{
    CacheIo,
    CacheConflict,
    CacheBusy,
    Canceled,
};
pub const Stage = enum { validate, bind, encode, assemble };
pub const Key = struct {
    compiler_version: []const u8,
    stage: Stage,
    target: program.profile.Target,
    model_sha256: []const u8,
    profile_sha256: []const u8,
    options_sha256: []const u8,
    inputs: lock.Lock,
};

pub fn key(arena: std.mem.Allocator, request: Key) Error!contracts.Digest {
    try lock.digest(request.model_sha256);
    try lock.digest(request.profile_sha256);
    try lock.digest(request.options_sha256);
    if (request.compiler_version.len == 0 or request.compiler_version.len > 128)
        return error.ProgramInvalid;
    try program.validation.inputValue(request.compiler_version, .{});
    var normalized = request;
    normalized.inputs = try lock.normalize(arena, request.inputs);
    const inputs = @constCast(normalized.inputs.inputs);
    // Acquisition location explains provenance but does not change the locked byte identity.
    for (inputs) |*input| input.origin = "locked";
    const bytes = try std.json.Stringify.valueAlloc(arena, normalized, .{});
    var result: contracts.Digest = undefined; // SAFETY: SHA-256 writes all bytes.
    std.crypto.hash.sha2.Sha256.hash(bytes, &result, .{});
    return result;
}

const Record = struct { schema: u32 = 1, sha256: []const u8, bytes: u64 };
pub const Hit = struct {
    file: std.Io.File,
    bytes: u64,
    sha256: contracts.Digest,

    pub fn close(hit: Hit, io: std.Io) void {
        hit.file.close(io);
    }
};

pub const Cache = struct {
    /// Caller owns this private cache directory and its handle for the cache lifetime.
    dir: std.Io.Dir,
    io: std.Io,
    arena: std.mem.Allocator,
    cancel: ?*const std.atomic.Value(bool) = null,

    pub fn get(self: Cache, identity: contracts.Digest) Error!?Hit {
        try self.canceled();
        const record = try self.readRecord(try self.recordName(identity)) orelse return null;
        if (record.schema != 1 or record.bytes > (contracts.Limits{}).expanded_bytes) return null;
        const expected = contracts.ids.parseHex32(record.sha256) orelse return null;
        const file = self.dir.openFile(self.io, record.sha256, .{
            .follow_symlinks = false,
        }) catch |err|
            return switch (err) {
                error.FileNotFound, error.SymLinkLoop => null,
                else => error.CacheIo,
            };
        errdefer file.close(self.io);
        const stat = file.stat(self.io) catch return error.CacheIo;
        if (stat.kind != .file or stat.size != record.bytes) {
            file.close(self.io);
            return null;
        }
        const actual = try self.hash(.{ .file = .{ .handle = file, .length = stat.size } });
        if (!std.mem.eql(u8, &actual, &expected)) {
            file.close(self.io);
            return null;
        }
        return .{ .file = file, .bytes = record.bytes, .sha256 = expected };
    }

    pub fn put(self: Cache, identity: contracts.Digest, source: content.Source) Error!void {
        try self.canceled();
        if (source.size() > (contracts.Limits{}).expanded_bytes) return error.ContentLimit;
        const lease = try self.acquire(identity);
        defer lease.close(self.io);
        const source_hash = try self.hash(source);
        if (try self.get(identity)) |previous| {
            defer previous.close(self.io);
            if (!std.mem.eql(u8, &source_hash, &previous.sha256)) return error.CacheConflict;
            return;
        }
        const blob_name = contracts.ids.hexDigest(source_hash);
        const pending = try self.pendingName();
        defer self.cleanup(pending);
        const file = self.dir.createFile(self.io, pending, .{
            .exclusive = true,
            .permissions = if (std.Io.File.Permissions.has_executable_bit)
                .fromMode(0o600)
            else
                .default_file,
        }) catch return error.CacheIo;
        {
            defer file.close(self.io);
            try self.copy(source, file, source_hash);
            file.sync(self.io) catch return error.CacheIo;
        }
        try self.canceled();
        self.dir.rename(pending, self.dir, &blob_name, self.io) catch return error.CacheIo;
        const record = try std.json.Stringify.valueAlloc(self.arena, Record{
            .sha256 = &blob_name,
            .bytes = source.size(),
        }, .{});
        try self.publishRecord(try self.recordName(identity), record);
    }

    fn readRecord(self: Cache, name: []const u8) Error!?Record {
        const file = self.dir.openFile(self.io, name, .{ .follow_symlinks = false }) catch |err|
            return switch (err) {
                error.FileNotFound, error.SymLinkLoop => null,
                else => error.CacheIo,
            };
        defer file.close(self.io);
        const stat = file.stat(self.io) catch return error.CacheIo;
        if (stat.kind != .file or stat.size > 4096) return null;
        const length = std.math.cast(usize, stat.size) orelse return null;
        const bytes = try self.arena.alloc(u8, length);
        const read = file.readPositionalAll(self.io, bytes, 0) catch return error.CacheIo;
        if (read != length) return null;
        return contracts.json.decode(Record, self.arena, bytes, .{
            .max_bytes = 4096,
            .max_schema = 1,
        }) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => null,
        };
    }

    fn acquire(self: Cache, identity: contracts.Digest) Error!std.Io.File {
        const name = try self.arena.print("{s}.lock", .{contracts.ids.hexDigest(identity)});
        for (0..2) |_| {
            const file = self.dir.openFile(self.io, name, .{
                .mode = .read_write,
                .follow_symlinks = false,
                .lock = .exclusive,
                .lock_nonblocking = true,
            }) catch |err| switch (err) {
                error.FileNotFound => self.dir.createFile(self.io, name, .{
                    .exclusive = true,
                    .read = true,
                    .permissions = if (std.Io.File.Permissions.has_executable_bit)
                        .fromMode(0o600)
                    else
                        .default_file,
                    .lock = .exclusive,
                    .lock_nonblocking = true,
                }) catch |creation| switch (creation) {
                    error.PathAlreadyExists => continue,
                    error.WouldBlock => return error.CacheBusy,
                    else => return error.CacheIo,
                },
                error.WouldBlock => return error.CacheBusy,
                else => return error.CacheIo,
            };
            errdefer file.close(self.io);
            const stat = file.stat(self.io) catch return error.CacheIo;
            if (stat.kind != .file or stat.nlink != 1) return error.CacheIo;
            return file;
        }
        return error.CacheBusy;
    }

    fn copy(
        self: Cache,
        source: content.Source,
        file: std.Io.File,
        expected: contracts.Digest,
    ) Error!void {
        var scratch: [64 << 10]u8 = undefined; // SAFETY: Source.read fills the used slice.
        var hash_state = std.crypto.hash.sha2.Sha256.init(.{});
        var offset: u64 = 0;
        while (offset < source.size()) {
            try self.canceled();
            const count = std.math.cast(usize, @min(scratch.len, source.size() - offset)) orelse
                return error.ContentLimit;
            try source.read(self.io, offset, scratch[0..count]);
            hash_state.update(scratch[0..count]);
            file.writeStreamingAll(self.io, scratch[0..count]) catch return error.CacheIo;
            offset += count;
        }
        if (!std.mem.eql(u8, &hash_state.finalResult(), &expected)) return error.LockMismatch;
    }

    fn hash(self: Cache, source: content.Source) Error!contracts.Digest {
        if (source.size() > (contracts.Limits{}).expanded_bytes) return error.ContentLimit;
        var scratch: [64 << 10]u8 = undefined; // SAFETY: Source.read fills the used slice.
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        var offset: u64 = 0;
        while (offset < source.size()) {
            try self.canceled();
            const count = std.math.cast(usize, @min(scratch.len, source.size() - offset)) orelse
                return error.ContentLimit;
            try source.read(self.io, offset, scratch[0..count]);
            hasher.update(scratch[0..count]);
            offset += count;
        }
        return hasher.finalResult();
    }

    fn publishRecord(self: Cache, name: []const u8, bytes: []const u8) Error!void {
        const pending = try self.pendingName();
        defer self.cleanup(pending);
        const file = self.dir.createFile(self.io, pending, .{
            .exclusive = true,
            .permissions = if (std.Io.File.Permissions.has_executable_bit)
                .fromMode(0o600)
            else
                .default_file,
        }) catch return error.CacheIo;
        {
            defer file.close(self.io);
            file.writeStreamingAll(self.io, bytes) catch return error.CacheIo;
            file.sync(self.io) catch return error.CacheIo;
        }
        try self.canceled();
        self.dir.rename(pending, self.dir, name, self.io) catch return error.CacheIo;
    }

    fn recordName(self: Cache, identity: contracts.Digest) Error![]const u8 {
        return self.arena.print("{s}.json", .{contracts.ids.hexDigest(identity)});
    }

    fn pendingName(self: Cache) Error![]const u8 {
        var random: [16]u8 = undefined; // SAFETY: random fills every byte.
        self.io.random(&random);
        return self.arena.print("pending-{s}", .{std.fmt.bytesToHex(random, .lower)});
    }

    fn canceled(self: Cache) Error!void {
        if (self.cancel) |flag| if (flag.load(.acquire)) return error.Canceled;
    }

    fn cleanup(self: Cache, name: []const u8) void {
        self.dir.deleteFile(self.io, name) catch |err| switch (err) {
            error.FileNotFound => {},
            else => std.log.warn("cache cleanup: {s}", .{@errorName(err)}),
        };
    }
};

test {
    _ = @import("cache_test.zig");
}
