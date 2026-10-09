//! Delete only unchanged owned resources. Unexpected objects and modified files survive.
const std = @import("std");
const contracts = @import("contracts");
const access = @import("access");
const policy = @import("access_policy");
const platform = @import("platform");
const program = @import("program");
const t = @import("types.zig");
const storage = @import("storage.zig");
const generation = @import("generation.zig");
const wire = @import("wire.zig");
const Error = t.Error;

pub fn retired(store: storage.Store, snapshot: t.RootState) Error!void {
    const directory = try generation.base(store.arena, snapshot.generation);
    const receipt_path = try store.arena.print("{s}/prepared.json", .{directory});
    if (!try store.exists(receipt_path)) return;
    const prepared = try generation.prepared(store, snapshot, null);
    const marker_path = try store.arena.print("{s}/cleanup", .{directory});
    const marker = try program.digest(store.arena, try wire.encode(store.arena, prepared));
    if (try store.read(marker_path, 64)) |existing| {
        if (!std.mem.eql(u8, marker, existing)) return error.KernelOwnership;
    } else try store.write(marker_path, marker);
    try writableDirectories(store, directory, snapshot, prepared);
    var index = snapshot.resources.len;
    while (index > 0) {
        index -= 1;
        const resource = snapshot.resources[index];
        const native = prepared.receipts[index];
        const path = try store.arena.print("{s}/data/{s}", .{ directory, resource.path });
        if (resource.kind == .directory) {
            try restoreDirectory(store, path, native);
        } else if (try generation.matches(store, path, resource, native, true)) {
            if (@import("builtin").os.tag == .windows and resource.link_directory) {
                try store.removeEmpty(path);
            } else try store.remove(path);
        }
    }
    try store.removeEmpty(try store.arena.print("{s}/data", .{directory}));
    if (try store.exists(try store.arena.print("{s}/data", .{directory}))) return;
    try store.remove(marker_path);
    try store.remove(receipt_path);
    try store.remove(try store.arena.print("{s}/intent", .{directory}));
    try store.removeEmpty(directory);
}

fn writableDirectories(
    store: storage.Store,
    directory: []const u8,
    snapshot: t.RootState,
    prepared: t.Prepared,
) Error!void {
    for (snapshot.resources, prepared.receipts) |resource, receipt| {
        if (resource.kind != .directory) continue;
        const path = try store.arena.print("{s}/data/{s}", .{ directory, resource.path });
        const opened = try openDirectory(store, path) orelse continue;
        defer opened.file.close(store.io);
        const prior = try access.decodeReceipt(
            store.arena,
            try program.decodeHex(
                store.arena,
                receipt.access_hex,
            ),
        );
        if (!sameObject(opened.observation, prior)) continue;
        const actual = try program.encodeHex(
            store.arena,
            try access.encodeReceipt(
                store.arena,
                opened.observation,
            ),
        );
        if (!std.mem.eql(u8, actual, receipt.access_hex)) {
            if (!policy.equal(
                opened.observation.policy,
                access.privatePolicy(
                    .directory,
                ),
            )) continue;
        }
        const changed = try access.apply(
            store.arena,
            store.io,
            opened.file,
            opened.observation,
            access.privatePolicy(.directory),
        );
        std.debug.assert(changed.policy.owner.write);
    }
}

fn restoreDirectory(store: storage.Store, path: []const u8, receipt: t.NativeReceipt) Error!void {
    const opened = try openDirectory(store, path) orelse return;
    defer opened.file.close(store.io);
    const prior = try access.decodeReceipt(
        store.arena,
        try program.decodeHex(
            store.arena,
            receipt.access_hex,
        ),
    );
    if (!sameObject(opened.observation, prior)) return;
    const actual = try program.encodeHex(
        store.arena,
        try access.encodeReceipt(
            store.arena,
            opened.observation,
        ),
    );
    if (!std.mem.eql(u8, actual, receipt.access_hex) and
        !policy.equal(opened.observation.policy, access.privatePolicy(.directory))) return;
    const parent = try store.openParent(path, false);
    defer parent.close(store.io);
    parent.dir.deleteDir(store.io, parent.name) catch |err| switch (err) {
        error.FileNotFound => return,
        error.DirNotEmpty => {
            const restored = try access.restore(
                store.arena,
                store.io,
                opened.file,
                opened.observation,
                prior,
            );
            std.debug.assert(policy.equal(restored.policy, prior.policy));
            return;
        },
        else => return platform.api.mapFs(err),
    };
    try storage.sync(store.io, parent.dir);
}

fn openDirectory(store: storage.Store, path: []const u8) Error!?access.File {
    const parent = store.openParent(path, false) catch |err| switch (err) {
        error.FsNotFound => return null,
        else => return err,
    };
    defer parent.close(store.io);
    const opened = access.openForAccess(store.arena, store.io, parent.dir, parent.name) catch |err|
        switch (err) {
            error.FsNotFound, error.AccessWrongKind, error.AccessConflict => return null,
            else => return err,
        };
    if (opened.observation.policy.kind != .directory) {
        opened.file.close(store.io);
        return null;
    }
    return opened;
}

fn sameObject(a: access.Observation, b: access.Observation) bool {
    return std.meta.eql(a.identity, b.identity) and a.owner.equal(b.owner);
}

/// An interrupted, unpublished prepare has no trusted completed receipt. Keep its private
/// bytes for explicit garbage collection; never infer ownership from a guessed pathname.
pub fn aborted(store: storage.Store, snapshot: t.RootState, plan_hash: []const u8) Error!void {
    const directory = try generation.base(store.arena, snapshot.generation);
    const path = try store.arena.print("{s}/prepared.json", .{directory});
    if (!try store.exists(path)) return;
    const receipt = try generation.prepared(store, snapshot, plan_hash);
    std.debug.assert(receipt.schema == 2);
    try retired(store, snapshot);
}
