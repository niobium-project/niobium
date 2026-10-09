const std = @import("std");
const cache = @import("cache.zig");
const program = @import("program");
const lock = @import("lock.zig");

test "N2-COMPILER-01: cache revalidates corrupt blobs and records and honors cancellation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var cancel = std.atomic.Value(bool).init(false);
    const io = std.testing.io;
    const a = arena.allocator();
    const store: cache.Cache = .{ .dir = tmp.dir, .io = io, .arena = a, .cancel = &cancel };
    const key_value: [32]u8 = @splat(42);
    try std.testing.expectEqual(null, try store.get(key_value));
    try store.put(key_value, .{ .bytes = "value" });
    const hit = (try store.get(key_value)).?;
    hit.close(io);
    try std.testing.expectError(error.CacheConflict, store.put(key_value, .{ .bytes = "other" }));
    const blob_name = try program.digest(a, "value");
    try tmp.dir.writeFile(io, .{ .sub_path = blob_name, .data = "wrong" });
    try std.testing.expectEqual(null, try store.get(key_value));
    try store.put(key_value, .{ .bytes = "value" });
    (try store.get(key_value)).?.close(io);
    cancel.store(true, .release);
    try std.testing.expectError(error.Canceled, store.put(key_value, .{ .bytes = "value" }));
    cancel.store(false, .release);
    const record = try a.print("{s}.json", .{std.fmt.bytesToHex(key_value, .lower)});
    try tmp.dir.writeFile(io, .{ .sub_path = record, .data = "invalid" });
    try std.testing.expectEqual(null, try store.get(key_value));
}

test "N2-COMPILER-01: concurrent cache writer leaves the published entry unchanged" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    const a = arena.allocator();
    const store: cache.Cache = .{ .dir = tmp.dir, .io = io, .arena = a };
    const identity: [32]u8 = @splat(7);
    try store.put(identity, .{ .bytes = "original" });
    const name = try a.print("{s}.lock", .{std.fmt.bytesToHex(identity, .lower)});
    const held = try tmp.dir.openFile(io, name, .{
        .mode = .read_write,
        .lock = .exclusive,
        .lock_nonblocking = true,
    });
    defer held.close(io);
    try std.testing.expectError(error.CacheBusy, store.put(identity, .{ .bytes = "replacement" }));
    const hit = (try store.get(identity)).?;
    defer hit.close(io);
    try std.testing.expectEqual(@as(u64, 8), hit.bytes);
}

test "N2-COMPILER-01: symbolic cache records never select a cached blob" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    const a = arena.allocator();
    const store: cache.Cache = .{ .dir = tmp.dir, .io = io, .arena = a };
    const identity: [32]u8 = @splat(8);
    try store.put(identity, .{ .bytes = "original" });
    const name = try a.print("{s}.json", .{std.fmt.bytesToHex(identity, .lower)});
    try tmp.dir.rename(name, tmp.dir, "other-record", io);
    try tmp.dir.symLink(io, "other-record", name, .{ .is_directory = false });
    try std.testing.expectEqual(null, try store.get(identity));
}

test "N2-COMPILER-01: semantic stage keys ignore acquisition paths but include target and bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const hash = try program.digest(a, "");
    var inputs = [_]lock.Input{.{
        .id = "payload",
        .kind = .content,
        .version = "1",
        .origin = "/first/source",
        .sha256 = hash,
        .bytes = 0,
    }};
    var request: cache.Key = .{
        .compiler_version = "2",
        .stage = .encode,
        .target = .@"x86_64-linux",
        .model_sha256 = hash,
        .profile_sha256 = hash,
        .options_sha256 = hash,
        .inputs = .{ .inputs = &inputs },
    };
    const first = try cache.key(a, request);
    inputs[0].origin = "/second/source";
    try std.testing.expectEqualSlices(u8, &first, &try cache.key(a, request));
    request.target = .@"x86_64-windows";
    try std.testing.expect(!std.mem.eql(u8, &first, &try cache.key(a, request)));
    request.target = .@"x86_64-linux";
    request.model_sha256 = try program.digest(a, "different");
    try std.testing.expect(!std.mem.eql(u8, &first, &try cache.key(a, request)));
}
