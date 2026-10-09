//! Run `create` and `probe` under different native accounts; never infer Everyone from owner.
const std = @import("std");
const access = @import("access");
const Dir = std.Io.Dir;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len == 2 and std.mem.eql(u8, args[1], "child")) std.process.exit(42);
    if (args.len != 3) return error.Usage;
    if (std.mem.eql(u8, args[1], "create")) {
        try create(init, args[2]);
    } else if (std.mem.eql(u8, args[1], "probe")) {
        try probe(init, args[2]);
    } else return error.Usage;
    try std.Io.File.stdout().writeStreamingAll(init.io, "PASS\n");
}

fn create(init: std.process.Init, parent_path: []const u8) !void {
    const arena = init.arena.allocator();
    const parent = try Dir.cwd().openDir(init.io, parent_path, .{});
    defer parent.close(init.io);
    const directory = try access.createDirectory(arena, init.io, parent, "objects");
    defer directory.dir.close(init.io);
    const source_path = try std.process.executablePathAlloc(init.io, arena);
    const source = try Dir.cwd().openFile(init.io, source_path, .{});
    defer source.close(init.io);
    const length = try source.length(init.io);
    if (length > 16 << 20) return error.ExecutableLimit;
    for ([_][]const u8{ "private", "read", "write", "execute.exe", "denied.exe" }, 0..) |name, i| {
        const made = try access.createFile(arena, init.io, directory.dir, name);
        defer made.file.close(init.io);
        var policy = access.privatePolicy(.file);
        if (i != 0) policy.everyone.read = true;
        if (i == 2) policy.everyone.write = true;
        if (i >= 3) {
            policy.owner.execute = true;
            policy.everyone.execute = i == 3;
            try copy(init.io, source, made.file, length);
        } else try made.file.writeStreamingAll(init.io, "payload");
        const final = try access.apply(arena, init.io, made.file, made.observation, policy);
        try made.file.sync(init.io);
        if (final.policy.everyone.bits() != policy.everyone.bits()) return error.WrongRights;
    }
    try access.syncDirectory(init.io, directory.dir);
    try access.syncDirectory(init.io, parent);
}

fn copy(io: std.Io, source: std.Io.File, target: std.Io.File, length: u64) !void {
    var bytes: [64 << 10]u8 = undefined; // SAFETY: exact positional reads fill consumed slices.
    var offset: u64 = 0;
    while (offset < length) {
        const count = std.math.cast(usize, @min(bytes.len, length - offset)) orelse
            return error.ExecutableLimit;
        const actual = try source.readPositionalAll(io, bytes[0..count], offset);
        if (actual != count) return error.ShortRead;
        try target.writeStreamingAll(io, bytes[0..count]);
        offset += count;
    }
}

fn probe(init: std.process.Init, parent_path: []const u8) !void {
    const arena = init.arena.allocator();
    const base = try std.fs.path.join(arena, &.{ parent_path, "objects" });
    std.log.info("principal probe: read public file", .{});
    const read = try Dir.cwd().openFile(init.io, try path(arena, base, "read"), .{});
    defer read.close(init.io);
    const observed = try access.inspect(arena, init.io, read);
    if (observed.owner.equal(try access.currentOwner(init.io))) return error.SamePrincipal;
    try listingDenied(init.io, base);
    std.log.info("principal probe: distinct owner verified; check denials", .{});
    try denied(init.io, try path(arena, base, "private"), .read_only);
    try denied(init.io, try path(arena, base, "read"), .read_write);
    const write = try Dir.cwd().openFile(init.io, try path(arena, base, "write"), .{
        .mode = .read_write,
    });
    defer write.close(init.io);
    try write.writePositionalAll(init.io, "changed", 0);
    try write.sync(init.io);
    std.log.info("principal probe: shared write verified; check execution", .{});
    if (@import("builtin").os.tag == .windows) {
        var code: u32 = 0;
        const executable = try arena.dupeSentinel(u8, try path(arena, base, "execute.exe"), 0);
        if (nb_access_fixture_spawn(executable, &code) != 0 or code != 42) {
            return error.WrongExecution;
        }
        const blocked = try arena.dupeSentinel(u8, try path(arena, base, "denied.exe"), 0);
        if (nb_access_fixture_spawn(blocked, &code) != 2) return error.ExecutionAllowed;
        return;
    }
    const executed = try std.process.run(arena, init.io, .{
        .argv = &.{ try path(arena, base, "execute.exe"), "child" },
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(1024),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } },
    });
    switch (executed.term) {
        .exited => |code| if (code != 42) return error.WrongExecution,
        else => return error.WrongExecution,
    }
    std.log.info("principal probe: allowed execution verified; check denied execution", .{});
    const unexpected = std.process.run(arena, init.io, .{
        .argv = &.{ try path(arena, base, "denied.exe"), "child" },
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(1024),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } },
    }) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    std.log.err("unexpected denied executable outcome: {t}", .{unexpected.term});
    return error.ExecutionAllowed;
}

extern fn nb_access_fixture_spawn([*:0]const u8, *u32) i32;

fn listingDenied(io: std.Io, base: []const u8) !void {
    const directory = Dir.cwd().openDir(io, base, .{ .iterate = true }) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    directory.close(io);
    return error.DirectoryListingAllowed;
}

fn path(arena: std.mem.Allocator, base: []const u8, name: []const u8) ![]const u8 {
    return std.fs.path.join(arena, &.{ base, name });
}

fn denied(io: std.Io, name: []const u8, mode: std.Io.Dir.OpenFileOptions.Mode) !void {
    const unexpected = Dir.cwd().openFile(io, name, .{ .mode = mode }) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    unexpected.close(io);
    return error.AccessAllowed;
}
