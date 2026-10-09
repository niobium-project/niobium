//! Strict portable access policies for host-owned native files and directories.
//! Creation is exclusive and private; callers write/verify content, apply policy, then publish.
const std = @import("std");
const builtin = @import("builtin");
const contracts = @import("contracts");
const b = @import("bindings.zig");
const t = @import("types.zig");
const p = @import("access_policy");
const receipt = @import("receipt.zig");
const backend = if (builtin.os.tag == .windows) @import("windows.zig") else @import("posix.zig");

pub const Error = t.Error;
pub const Kind = p.Kind;
pub const Rights = p.Rights;
pub const Policy = p.Policy;
pub const Owner = t.Owner;
pub const Identity = t.Identity;
pub const Observation = t.Observation;
pub const validate = p.validate;
pub const privatePolicy = p.private;
pub const File = struct { file: std.Io.File, observation: Observation };
pub const Directory = struct { dir: std.Io.Dir, observation: Observation };

pub fn currentOwner(io: std.Io) Error!Owner {
    try io.checkCancel();
    var owner: Owner = .{};
    var length: u32 = 0;
    try t.status(b.nb_access_current_owner(&owner.bytes, owner.bytes.len, &length));
    if (length == 0 or length > owner.bytes.len) return error.AccessReceiptInvalid;
    owner.length = std.math.cast(u8, length) orelse return error.AccessLimit;
    return owner;
}

pub fn inspect(arena: std.mem.Allocator, io: std.Io, file: std.Io.File) Error!Observation {
    try io.checkCancel();
    return backend.inspect(arena, try handle(file.handle));
}

pub fn apply(
    arena: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    expected: Observation,
    policy: Policy,
) Error!Observation {
    try validate(policy);
    const current = try precondition(arena, io, file, expected);
    if (current.policy.kind != policy.kind) return error.AccessWrongKind;
    try backend.apply(try handle(file.handle), current, policy);
    const result = try inspect(arena, io, file);
    if (!std.meta.eql(result.identity, current.identity) or !result.owner.equal(current.owner))
        return error.AccessDrift;
    if (!p.equal(result.policy, policy)) return error.AccessDrift;
    return result;
}

pub fn restore(
    arena: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    expected_current: Observation,
    prior: Observation,
) Error!Observation {
    try backend.validateObservation(prior);
    const current = try precondition(arena, io, file, expected_current);
    if (!std.meta.eql(current.identity, prior.identity) or !current.owner.equal(prior.owner) or
        current.policy.kind != prior.policy.kind) return error.AccessConflict;
    try backend.restore(try handle(file.handle), current, prior);
    const result = try inspect(arena, io, file);
    if (!receipt.same(result, prior)) return error.AccessDrift;
    return result;
}

fn precondition(
    arena: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    expected: Observation,
) Error!Observation {
    try backend.validateObservation(expected);
    const current = try inspect(arena, io, file);
    if (!receipt.same(current, expected)) return error.AccessDrift;
    if (!current.owner.equal(try currentOwner(io))) return error.AccessOwnerMismatch;
    return current;
}

pub fn encodeReceipt(arena: std.mem.Allocator, value: Observation) Error![]const u8 {
    try backend.validateObservation(value);
    return receipt.encode(arena, value);
}

pub fn decodeReceipt(arena: std.mem.Allocator, bytes: []const u8) Error!Observation {
    const value = try receipt.decode(arena, bytes);
    try backend.validateObservation(value);
    return value;
}

pub fn fingerprint(arena: std.mem.Allocator, value: Observation) Error![32]u8 {
    const bytes = try encodeReceipt(arena, value);
    var digest: [32]u8 = undefined; // SAFETY: hash writes every byte.
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

pub fn directoryFile(dir: std.Io.Dir) std.Io.File {
    return .{ .handle = dir.handle, .flags = .{ .nonblocking = false } };
}

/// Keep already authorized native write access through final policy assignment and flush.
/// This reopens the same directory without changing its access policy.
pub fn reopenMutableDirectory(
    arena: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
) Error!File {
    try io.checkCancel();
    try backend.parentSafe(try handle(dir.handle));
    var native: usize = 0;
    try t.status(b.nb_access_reopen_directory(try handle(dir.handle), &native));
    const file = try nativeFile(native);
    errdefer file.close(io);
    const observed = try inspect(arena, io, file);
    if (observed.policy.kind != .directory) return error.AccessWrongKind;
    if (!observed.policy.owner.write) return error.AccessConflict;
    if (!observed.owner.equal(try currentOwner(io))) return error.AccessOwnerMismatch;
    return .{ .file = file, .observation = observed };
}

/// Flush an existing writable directory without interpreting or changing an unmanaged
/// parent's ACL. Native access checks still apply; no backup/elevation authority is added.
pub fn syncDirectory(io: std.Io, dir: std.Io.Dir) Error!void {
    try io.checkCancel();
    try backend.parentSafe(try handle(dir.handle));
    var native: usize = 0;
    try t.status(b.nb_access_reopen_directory(try handle(dir.handle), &native));
    const file = try nativeFile(native);
    defer file.close(io);
    file.sync(io) catch |err| return @import("platform").api.mapFs(err);
}

/// Reopen for permission recovery. The portable profile retains owner read access.
pub fn openForAccess(
    arena: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    name: []const u8,
) Error!File {
    try nameValid(name);
    try io.checkCancel();
    const directory = try handle(parent.handle);
    try backend.parentSafe(directory);
    const terminated = try arena.dupeSentinel(u8, name, 0);
    var native: usize = 0;
    try t.status(b.nb_access_open(directory, terminated, &native));
    const file = try nativeFile(native);
    errdefer file.close(io);
    return .{ .file = file, .observation = try inspect(arena, io, file) };
}

pub fn createFile(
    arena: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    name: []const u8,
) Error!File {
    return create(arena, io, parent, name, .file);
}

pub fn createDirectory(
    arena: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    name: []const u8,
) Error!Directory {
    const result = try create(arena, io, parent, name, .directory);
    return .{ .dir = .{ .handle = result.file.handle }, .observation = result.observation };
}

fn create(
    arena: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    name: []const u8,
    kind: Kind,
) Error!File {
    try nameValid(name);
    const owner = try currentOwner(io);
    const directory = try handle(parent.handle);
    try backend.parentSafe(directory);
    const terminated = try arena.dupeSentinel(u8, name, 0);
    var native: usize = 0;
    var acl_buffer: [128]u8 align(4) = undefined; // SAFETY: acl fills its returned prefix.
    const acl = if (builtin.os.tag == .windows)
        (try backend.acl(owner, p.private(kind), &acl_buffer)).ptr
    else
        null;
    try t.status(b.nb_access_create(
        directory,
        terminated,
        @backingInt(kind),
        if (kind == .file) 0o600 else 0o700,
        &owner.bytes,
        acl,
        &native,
    ));
    const file = try nativeFile(native);
    errdefer file.close(io);
    try backend.prepareNew(native, kind);
    const observation = try inspect(arena, io, file);
    if (!observation.owner.equal(owner)) return error.AccessOwnerMismatch;
    if (!p.equal(observation.policy, p.private(kind))) return error.AccessDrift;
    return .{ .file = file, .observation = observation };
}

fn nameValid(name: []const u8) Error!void {
    if (name.len == 0 or name.len > (contracts.Limits{}).path_bytes or name.len > 1024)
        return error.AccessLimit;
    if (!std.unicode.utf8ValidateSlice(name)) return error.AccessPolicyInvalid;
    if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, ".."))
        return error.AccessPolicyInvalid;
    for (name) |byte| {
        if (byte == '/' or byte == 0)
            return error.AccessPolicyInvalid;
        if (builtin.os.tag == .windows and (byte == '\\' or byte == ':'))
            return error.AccessPolicyInvalid;
    }
}

fn handle(value: std.Io.File.Handle) Error!usize {
    if (builtin.os.tag == .windows) return @intFromPtr(value);
    return std.math.cast(usize, value) orelse error.AccessWrongKind;
}

test {
    _ = p;
}

fn nativeFile(value: usize) Error!std.Io.File {
    return .{
        .handle = if (builtin.os.tag == .windows) @ptrFromInt(value) else fd: {
            break :fd std.math.cast(std.posix.fd_t, value) orelse return error.AccessLimit;
        },
        .flags = .{ .nonblocking = false },
    };
}
