//! Generation materialization and readback. The coordinator decides before publication.
const std = @import("std");
const contracts = @import("contracts");
const access = @import("access");
const policy = @import("access_policy");
const platform = @import("platform");
const program = @import("program");
const t = @import("types.zig");
const storage = @import("storage.zig");
const containers = @import("containers.zig");
const wire = @import("wire.zig");
const Error = t.Error;

pub fn base(arena: std.mem.Allocator, generation: []const u8) Error![]const u8 {
    try wire.nonce(generation);
    return arena.print(storage.metadata ++ "/generations/{s}", .{generation});
}

pub fn prepare(
    store: storage.Store,
    snapshot: t.RootState,
    inventory: containers.Inventory.Root,
    plan_hash: []const u8,
    hook: t.Checkpoint,
) Error!void {
    const directory = try base(store.arena, snapshot.generation);
    if (try store.exists(directory)) return error.KernelConflict;
    const gen = try store.createDir(directory);
    defer gen.close(store.io);
    try store.write(try store.arena.print("{s}/intent", .{directory}), plan_hash);
    const data = try store.createDir(try store.arena.print("{s}/data", .{directory}));
    defer data.close(store.io);
    var receipts: std.ArrayList(t.NativeReceipt) = .empty;
    for (inventory.items) |item| {
        const path = try store.arena.print("{s}/data/{s}", .{ directory, item.resource.path });
        const receipt = try create(store, path, item);
        try receipts.append(store.arena, receipt);
        hook.reach("resource-written", store.binding.id);
    }
    // Children are complete before their directories become non-writable.
    var index = inventory.items.len;
    while (index > 0) {
        index -= 1;
        const item = inventory.items[index];
        if (item.resource.kind != .directory) continue;
        const path = try store.arena.print("{s}/data/{s}", .{ directory, item.resource.path });
        receipts.items[index] = try finishDirectory(store, path, item.resource);
    }
    try storage.sync(store.io, data);
    const complete: t.Prepared = .{
        .plan_sha256 = plan_hash,
        .root = snapshot.id,
        .receipts = receipts.items,
    };
    try store.write(
        try store.arena.print("{s}/prepared.json", .{directory}),
        try wire.encode(store.arena, complete),
    );
    try verify(store, snapshot, plan_hash, true);
    hook.reach("root-prepared", store.binding.id);
}

fn create(store: storage.Store, path: []const u8, item: containers.Item) Error!t.NativeReceipt {
    const parent = try store.openParent(path, false);
    defer parent.close(store.io);
    switch (item.resource.kind) {
        .directory => {
            const made = try access.createDirectory(store.arena, store.io, parent.dir, parent.name);
            defer made.dir.close(store.io);
            try storage.sync(store.io, parent.dir);
            return .{
                .path = item.resource.path,
                .access_hex = try program.encodeHex(
                    store.arena,
                    try access.encodeReceipt(
                        store.arena,
                        made.observation,
                    ),
                ),
            };
        },
        .file => {
            const made = try access.createFile(store.arena, store.io, parent.dir, parent.name);
            defer made.file.close(store.io);
            const digest = try containers.copy(store.io, item.body, made.file);
            if (!std.mem.eql(u8, &digest, &item.resource.sha256)) return error.ProgramDigest;
            const observed = try access.apply(
                store.arena,
                store.io,
                made.file,
                made.observation,
                item.resource.policy,
            );
            made.file.sync(store.io) catch |err| return platform.api.mapFs(err);
            try storage.sync(store.io, parent.dir);
            return .{
                .path = item.resource.path,
                .access_hex = try program.encodeHex(
                    store.arena,
                    try access.encodeReceipt(
                        store.arena,
                        observed,
                    ),
                ),
            };
        },
        .symlink => {
            parent.dir.symLink(store.io, item.resource.link_target, parent.name, .{
                .is_directory = item.resource.link_directory,
            }) catch |err|
                return if (@import("builtin").os.tag == .windows and
                    (err == error.AccessDenied or err == error.PermissionDenied))
                    error.KernelUnsupported
                else
                    platform.api.mapFs(err);
            try storage.sync(store.io, parent.dir);
            const stat = parent.dir.statFile(
                store.io,
                parent.name,
                .{
                    .follow_symlinks = false,
                },
            ) catch |err| return platform.api.mapFs(err);
            if (stat.kind != .sym_link) return error.KernelUnsupported;
            return .{
                .path = item.resource.path,
                .link_inode = inodeIdentity(stat.inode),
                .link_target = try wire.nativeLinkTarget(store.arena, item.resource.link_target),
            };
        },
    }
}

fn finishDirectory(
    store: storage.Store,
    path: []const u8,
    resource: t.Resource,
) Error!t.NativeReceipt {
    const parent = try store.openParent(path, false);
    defer parent.close(store.io);
    const dir = parent.dir.openDir(store.io, parent.name, .{
        .follow_symlinks = false,
    }) catch |err| return platform.api.mapFs(err);
    defer dir.close(store.io);
    const opened = try access.reopenMutableDirectory(store.arena, store.io, dir);
    defer opened.file.close(store.io);
    const after = try access.apply(
        store.arena,
        store.io,
        opened.file,
        opened.observation,
        resource.policy,
    );
    opened.file.sync(store.io) catch |err| return platform.api.mapFs(err);
    return .{
        .path = resource.path,
        .access_hex = try program.encodeHex(
            store.arena,
            try access.encodeReceipt(
                store.arena,
                after,
            ),
        ),
    };
}

pub fn prepared(
    store: storage.Store,
    snapshot: t.RootState,
    plan_hash: ?[]const u8,
) Error!t.Prepared {
    const directory = try base(store.arena, snapshot.generation);
    const path = try store.arena.print("{s}/prepared.json", .{directory});
    const bytes = try store.read(path, contracts.limits.default.runtime_plan_bytes) orelse
        return error.KernelState;
    const value = try wire.decode(t.Prepared, store.arena, bytes);
    if (value.schema != 2) return error.KernelUnsupported;
    try wire.hash(value.plan_sha256);
    if (!std.mem.eql(u8, value.root, snapshot.id) or
        value.receipts.len != snapshot.resources.len) return error.KernelState;
    if (plan_hash) |expected| {
        if (!std.mem.eql(u8, value.plan_sha256, expected)) return error.KernelState;
    }
    for (value.receipts, snapshot.resources) |receipt, resource| {
        if (!std.mem.eql(u8, receipt.path, resource.path)) return error.KernelState;
        if (resource.kind == .symlink) {
            if (receipt.access_hex.len != 0 or
                !std.mem.eql(
                    u8,
                    receipt.link_target,
                    try wire.nativeLinkTarget(store.arena, resource.link_target),
                )) return error.KernelState;
        } else {
            const native = try access.decodeReceipt(
                store.arena,
                try program.decodeHex(
                    store.arena,
                    receipt.access_hex,
                ),
            );
            if (!policy.equal(native.policy, resource.policy)) return error.KernelState;
            if (receipt.link_target.len != 0 or receipt.link_inode != 0) return error.KernelState;
        }
    }
    return value;
}

pub fn verify(
    store: storage.Store,
    snapshot: t.RootState,
    hash: ?[]const u8,
    content: bool,
) Error!void {
    const receipt = try prepared(store, snapshot, hash);
    const directory = try base(store.arena, snapshot.generation);
    for (snapshot.resources, receipt.receipts) |resource, native| {
        const path = try store.arena.print("{s}/data/{s}", .{ directory, resource.path });
        if (!try matches(store, path, resource, native, content)) return error.KernelDrift;
    }
}

pub fn matches(
    store: storage.Store,
    path: []const u8,
    resource: t.Resource,
    receipt: t.NativeReceipt,
    check_content: bool,
) Error!bool {
    const parent = store.openParent(path, false) catch |err| switch (err) {
        error.FsNotFound => return false,
        else => return err,
    };
    defer parent.close(store.io);
    const stat = parent.dir.statFile(store.io, parent.name, .{
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return platform.api.mapFs(err),
    };
    if (resource.kind == .symlink) {
        if (stat.kind != .sym_link or inodeIdentity(stat.inode) != receipt.link_inode) return false;
        // SAFETY: readLink fills the returned prefix before it is observed.
        var buffer: [contracts.limits.default.path_bytes]u8 = undefined;
        const length = parent.dir.readLink(store.io, parent.name, &buffer) catch |err|
            return platform.api.mapFs(err);
        return std.mem.eql(u8, buffer[0..length], receipt.link_target);
    }
    const kind: std.Io.File.Kind = if (resource.kind == .directory) .directory else .file;
    if (stat.kind != kind) return false;
    const opened = access.openForAccess(store.arena, store.io, parent.dir, parent.name) catch |err|
        switch (err) {
            error.AccessConflict, error.AccessDrift, error.AccessOwnerMismatch => return false,
            else => return err,
        };
    defer opened.file.close(store.io);
    const actual = try program.encodeHex(
        store.arena,
        try access.encodeReceipt(
            store.arena,
            opened.observation,
        ),
    );
    if (!std.mem.eql(u8, actual, receipt.access_hex)) return false;
    if (!check_content or resource.kind != .file) return true;
    const file = try store.openFile(path);
    defer file.close(store.io);
    const size = file.length(store.io) catch |err| return platform.api.mapFs(err);
    if (size != resource.bytes) return false;
    const digest = try containers.hashBody(
        store.io,
        .{
            .source = .{ .file = .{
                .handle = file,
                .length = size,
            } },
            .length = size,
        },
    );
    return std.mem.eql(u8, &digest, &resource.sha256);
}

fn inodeIdentity(value: std.Io.File.INode) u128 {
    if (comptime @import("builtin").os.tag == .windows) return @as(u64, @bitCast(value));
    return value;
}
