//! Native permission checks: run this same test binary on each qualified target.
const std = @import("std");
const builtin = @import("builtin");
const access = @import("access");
extern fn nb_access_fixture_inherit(usize, u32) i32;
extern fn nb_access_fixture_root() i32;

fn descriptor(file: std.Io.File) usize {
    return if (builtin.os.tag == .windows) @intFromPtr(file.handle) else @intCast(file.handle);
}

const read_only: access.Policy = .{
    .kind = .file,
    .owner = .{ .read = true },
    .everyone = .{},
};

test "N2-ACCESS-01: file creation, content-independent receipt and exact rollback" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const created = try access.createFile(a, io, temp.dir, "payload");
    defer created.file.close(io);
    const before = try access.fingerprint(a, created.observation);
    try created.file.writeStreamingAll(io, "payload bytes");
    try created.file.sync(io);
    const written = try access.inspect(a, io, created.file);
    try std.testing.expectEqualSlices(u8, &before, &(try access.fingerprint(a, written)));
    const durable = try access.encodeReceipt(a, written);
    const decoded = try access.decodeReceipt(a, durable);
    const changed = try access.apply(a, io, created.file, decoded, read_only);
    try std.testing.expect(!std.mem.eql(u8, &before, &(try access.fingerprint(a, changed))));
    try std.testing.expectError(
        error.AccessDrift,
        access.apply(a, io, created.file, decoded, read_only),
    );
    const restored = try access.restore(a, io, created.file, changed, decoded);
    try std.testing.expectEqualSlices(u8, &before, &(try access.fingerprint(a, restored)));
    const content = try temp.dir.readFileAlloc(io, "payload", a, .limited(32));
    try std.testing.expectEqualStrings("payload bytes", content);
}

test "N2-ACCESS-01: OS denies a new owner write-open after read-only policy" {
    if (nb_access_fixture_root() != 0) return error.SkipZigTest;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const created = try access.createFile(a, io, temp.dir, "readonly");
    defer created.file.close(io);
    const changed = try access.apply(a, io, created.file, created.observation, read_only);
    const reader = try temp.dir.openFile(io, "readonly", .{ .mode = .read_only });
    reader.close(io);
    if (temp.dir.openFile(io, "readonly", .{ .mode = .read_write })) |writer| {
        writer.close(io);
        return error.TestUnexpectedResult;
    } else |err| {
        try std.testing.expect(err == error.AccessDenied or err == error.PermissionDenied);
    }
    const restored = try access.restore(a, io, created.file, changed, created.observation);
    const writer = try temp.dir.openFile(io, "readonly", .{ .mode = .read_write });
    writer.close(io);
    try std.testing.expect(restored.policy.owner.write);
}

test "N2-ACCESS-01: directory policy always permits traversal but controls listing and changes" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const created = try access.createDirectory(a, io, temp.dir, "directory");
    defer created.dir.close(io);
    const file = access.directoryFile(created.dir);
    const policy: access.Policy = .{
        .kind = .directory,
        .owner = .{ .read = true, .write = true },
        .everyone = .{ .read = true },
    };
    const observed = try access.apply(a, io, file, created.observation, policy);
    try std.testing.expect(observed.policy.everyone.read);
    try std.testing.expect(!observed.policy.everyone.write);
    if (builtin.os.tag != .windows) {
        const native = try file.stat(io);
        try std.testing.expectEqual(@as(u32, 0o755), native.permissions.toMode() & 0o777);
    }
}

test "N2-ACCESS-01: inherited ACL context is normalized or explicitly refused before content" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const parent = try access.createDirectory(a, io, temp.dir, "parent");
    defer parent.dir.close(io);
    const fixture = nb_access_fixture_inherit(descriptor(access.directoryFile(parent.dir)), 1);
    if (fixture == 3) return error.SkipZigTest;
    try std.testing.expectEqual(@as(i32, 0), fixture);
    if (builtin.os.tag == .macos) {
        try std.testing.expectError(
            error.AccessUnsupported,
            access.createFile(a, io, parent.dir, "child"),
        );
        try std.testing.expectError(error.FileNotFound, parent.dir.access(io, "child", .{}));
    } else {
        const child = try access.createFile(a, io, parent.dir, "child");
        defer child.file.close(io);
        try std.testing.expect(!child.observation.policy.everyone.read);
        const nested = try access.createDirectory(a, io, parent.dir, "nested");
        defer nested.dir.close(io);
        const observation = try access.inspect(a, io, access.directoryFile(nested.dir));
        try std.testing.expect(!observation.policy.everyone.write);
    }
}

test "N2-ACCESS-01: exclusive creation cannot replace or address another resource" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const created = try access.createFile(a, io, temp.dir, "existing");
    defer created.file.close(io);
    try created.file.writeStreamingAll(io, "keep");
    try std.testing.expectError(error.AccessExists, access.createFile(a, io, temp.dir, "existing"));
    for ([_][]const u8{ "../escape", ".", "bad\x00name" }) |path| {
        try std.testing.expectError(
            error.AccessPolicyInvalid,
            access.createFile(a, io, temp.dir, path),
        );
    }
    if (@import("builtin").os.tag == .windows) {
        try std.testing.expectError(
            error.AccessPolicyInvalid,
            access.createFile(
                a,
                io,
                temp.dir,
                "file:stream",
            ),
        );
    } else {
        const colon = try access.createFile(a, io, temp.dir, "file:stream");
        colon.file.close(io);
    }
    try std.testing.expectEqualStrings(
        "keep",
        try temp.dir.readFileAlloc(io, "existing", a, .limited(32)),
    );
}

test "N2-ACCESS-01: malformed or wrong-object receipts cannot mutate permissions" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const first = try access.createFile(a, io, temp.dir, "first");
    defer first.file.close(io);
    const second = try access.createFile(a, io, temp.dir, "second");
    defer second.file.close(io);
    try std.testing.expectError(
        error.AccessDrift,
        access.apply(a, io, second.file, first.observation, read_only),
    );
    const bytes = try a.dupe(u8, try access.encodeReceipt(a, first.observation));
    bytes[8] = 2;
    try std.testing.expectError(error.AccessReceiptInvalid, access.decodeReceipt(a, bytes));
    bytes[8] = 1;
    bytes[16] = 255;
    try std.testing.expectError(error.AccessReceiptInvalid, access.decodeReceipt(a, bytes));
    const observed = try access.inspect(a, io, first.file);
    try std.testing.expect(observed.policy.owner.write);
}

test {
    _ = access;
}

test "N2-ACCESS-01: existing unknown ACLs are not merged or overwritten" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const created = try access.createFile(a, io, temp.dir, "foreign-acl");
    defer created.file.close(io);
    const result = nb_access_fixture_inherit(descriptor(created.file), 0);
    if (result == 3) return error.SkipZigTest;
    try std.testing.expectEqual(@as(i32, 0), result);
    try std.testing.expectError(
        error.AccessConflict,
        access.apply(a, io, created.file, created.observation, read_only),
    );
    try std.testing.expectError(error.AccessConflict, access.inspect(a, io, created.file));
}

test "N2-ACCESS-01: shared inodes cannot receive private-object permission changes" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const created = try access.createFile(a, io, temp.dir, "original");
    defer created.file.close(io);
    try std.testing.expectEqual(@as(i32, 0), nb_access_fixture_link(
        descriptor(access.directoryFile(temp.dir)),
        "original",
        "alias",
    ));
    try std.testing.expectError(
        error.AccessConflict,
        access.apply(a, io, created.file, created.observation, read_only),
    );
    try temp.dir.deleteFile(io, "alias");
    const observed = try access.inspect(a, io, created.file);
    try std.testing.expect(observed.policy.owner.write);
}

extern fn nb_access_fixture_execute(usize, [*:0]const u8) i32;
extern fn nb_access_fixture_link(usize, [*:0]const u8, [*:0]const u8) i32;

test "N2-ACCESS-01: directory finalization retains authorized flush handle" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const made = try access.createDirectory(a, io, temp.dir, "finalized");
    defer made.dir.close(io);
    const writable = try access.reopenMutableDirectory(a, io, made.dir);
    defer writable.file.close(io);
    var readonly = access.privatePolicy(.directory);
    readonly.owner.write = false;
    const observed = try access.apply(a, io, writable.file, writable.observation, readonly);
    try writable.file.sync(io);
    const actual = try access.inspect(a, io, writable.file);
    try std.testing.expectEqualSlices(
        u8,
        try access.encodeReceipt(
            a,
            observed,
        ),
        try access.encodeReceipt(
            a,
            actual,
        ),
    );
    const restored = try access.restore(a, io, writable.file, actual, writable.observation);
    try std.testing.expect(restored.policy.owner.write);
    try access.syncDirectory(io, made.dir);
}

test "N2-ACCESS-01: execution grants are checked by the native kernel" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const created = try access.createFile(a, io, temp.dir, "executable");
    defer created.file.close(io);
    const parent = descriptor(access.directoryFile(temp.dir));
    try std.testing.expectEqual(@as(i32, 2), nb_access_fixture_execute(parent, "executable"));
    const policy: access.Policy = .{
        .kind = .file,
        .owner = .{ .read = true, .execute = true },
        .everyone = .{ .read = true, .execute = true },
    };
    const applied = try access.apply(a, io, created.file, created.observation, policy);
    try std.testing.expect(applied.policy.owner.execute);
    try std.testing.expectEqual(@as(i32, 0), nb_access_fixture_execute(parent, "executable"));
}

test "N2-ACCESS-01: serialized receipt restores after all creation handles have closed" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const io = std.testing.io;
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const created = try access.createFile(a, io, temp.dir, "locked");
        defer created.file.close(io);
        try created.file.writeStreamingAll(io, "retained content");
        try created.file.sync(io);
        try temp.dir.writeFile(io, .{
            .sub_path = "prior.receipt",
            .data = try access.encodeReceipt(a, created.observation),
        });
        const changed = try access.apply(a, io, created.file, created.observation, .{
            .kind = .file,
            .owner = .{ .read = true },
            .everyone = .{},
        });
        try std.testing.expect(!changed.policy.owner.write);
    }
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const stored = try temp.dir.readFileAlloc(io, "prior.receipt", a, .limited(128 << 10));
    const prior = try access.decodeReceipt(a, stored);
    const reopened = try access.openForAccess(a, io, temp.dir, "locked");
    defer reopened.file.close(io);
    try std.testing.expect(!reopened.observation.policy.owner.write);
    const restored = try access.restore(a, io, reopened.file, reopened.observation, prior);
    try std.testing.expect(restored.policy.owner.write);
    try std.testing.expectEqualStrings(
        "retained content",
        try temp.dir.readFileAlloc(io, "locked", a, .limited(32)),
    );
}
