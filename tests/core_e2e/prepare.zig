//! Publish isolated test inputs before invoking the production compiler.
const std = @import("std");
const compiler = @import("compiler");
const program = @import("program");
const content = @import("content");
const products = @import("products.zig");
const Dir = std.Io.Dir;
pub const Paths = struct {
    runtime: []const u8,
    metadata: []const u8,
    worker: []const u8,
    signer: ?[]const u8,
    files: []const u8,
    consumer: []const u8,
};
pub const Input = struct { entry: compiler.lock.Input, path: []const u8 };
pub const Prepared = struct {
    directory: []const u8,
    lock_path: []const u8,
    inputs: []const Input,
    assets: products.Assets,
};

pub fn create(
    arena: std.mem.Allocator,
    io: std.Io,
    directory: []const u8,
    target: program.profile.Target,
    paths: Paths,
) !Prepared {
    try Dir.cwd().createDir(io, directory, .default_dir);
    const dir = try Dir.cwd().openDir(io, directory, .{});
    defer dir.close(io);
    var entries: std.ArrayList(Input) = .empty;
    var runtime = try copy(arena, io, dir, directory, "runtime", paths.runtime, .runtime);
    var metadata = try copy(
        arena,
        io,
        dir,
        directory,
        "runtime-metadata",
        paths.metadata,
        .runtime_metadata,
    );
    const bytes = try dir.readFileAlloc(io, "runtime-metadata", arena, .limited(1 << 20));
    const package = try compiler.runtime_package.decode(arena, bytes);
    if (!std.mem.eql(u8, package.template_sha256, runtime.entry.sha256) or
        package.template_bytes != runtime.entry.bytes or package.profile.target != target)
        return error.FixtureChanged;
    runtime.entry.target = target;
    runtime.entry.version = package.version;
    metadata.entry.version = package.version;
    runtime.entry.dependencies = &.{"runtime-metadata"};
    try entries.append(arena, runtime);
    try entries.append(arena, metadata);
    try entries.append(arena, try copy(arena, io, dir, directory, "worker", paths.worker, .tool));
    if (paths.signer) |signer| try entries.append(
        arena,
        try copy(arena, io, dir, directory, "signer", signer, .tool),
    );
    const files = try copy(arena, io, dir, directory, "files", paths.files, .library);
    const consumer = try copy(arena, io, dir, directory, "consumer", paths.consumer, .library);
    try entries.append(arena, files);
    try entries.append(arena, consumer);
    const assets: products.Assets = .{
        .files = library(files, "libs/files.wasm"),
        .consumer = library(consumer, "libs/consumer.wasm"),
        .primary = try payload(arena, io, dir, "primary", true),
        .fallback = try payload(arena, io, dir, "fallback", false),
    };
    for ([_][]const u8{ "primary", "fallback" }) |id|
        try entries.append(arena, try describe(arena, io, directory, id, .content));
    const locked = try arena.alloc(compiler.lock.Input, entries.items.len);
    for (entries.items, locked) |input, *entry| entry.* = input.entry;
    const lock_path = try std.fs.path.join(arena, &.{ directory, "inputs.lock.json" });
    try Dir.cwd().writeFile(
        io,
        .{ .sub_path = lock_path, .data = try compiler.lock.encode(arena, .{ .inputs = locked }) },
    );
    return .{
        .directory = directory,
        .lock_path = lock_path,
        .inputs = entries.items,
        .assets = assets,
    };
}

pub fn models(
    arena: std.mem.Allocator,
    io: std.Io,
    prepared: Prepared,
    target: program.profile.Target,
) !void {
    const cases = .{
        .{ "files", false, @as(u32, 1), true },
        .{ "tools-v1", true, @as(u32, 1), true },
        .{ "tools-v2", true, @as(u32, 2), true },
        .{ "tools-invalid", true, @as(u32, 2), false },
    };
    inline for (cases) |case| {
        try Dir.cwd().writeFile(io, .{
            .sub_path = try arena.print("{s}/{s}.program.json", .{ prepared.directory, case[0] }),
            .data = try products.build(arena, target, prepared.assets, case[1], case[2], case[3]),
        });
    }
}

fn copy(
    arena: std.mem.Allocator,
    io: std.Io,
    dir: Dir,
    directory: []const u8,
    id: []const u8,
    source: []const u8,
    kind: compiler.lock.Kind,
) !Input {
    const executable = kind == .runtime or kind == .tool;
    try Dir.cwd().copyFile(source, dir, id, io, .{
        .permissions = if (executable) .executable_file else .default_file,
    });
    return describe(arena, io, directory, id, kind);
}

fn describe(
    arena: std.mem.Allocator,
    io: std.Io,
    directory: []const u8,
    id: []const u8,
    kind: compiler.lock.Kind,
) !Input {
    const path = try std.fs.path.join(arena, &.{ directory, id });
    const file = try Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const size = (try file.stat(io)).size;
    if (size > 64 << 20) return error.FixtureLimit;
    var buffer: [64 << 10]u8 = undefined; // SAFETY: reads fill every hashed slice.
    var digest: std.crypto.hash.sha2.Sha256 = .init(.{});
    var offset: u64 = 0;
    while (offset < size) {
        const count = std.math.cast(usize, @min(size - offset, buffer.len)) orelse
            return error.FixtureLimit;
        if (try file.readPositionalAll(io, buffer[0..count], offset) != count)
            return error.FixtureChanged;
        digest.update(buffer[0..count]);
        offset += count;
    }
    return .{
        .path = path,
        .entry = .{
            .id = id,
            .kind = kind,
            .version = "1",
            .origin = id,
            .sha256 = try arena.dupe(u8, &std.fmt.bytesToHex(digest.finalResult(), .lower)),
            .bytes = size,
        },
    };
}

fn library(input: Input, member: []const u8) program.model.Library {
    return .{
        .id = input.entry.id,
        .member = member,
        .sha256 = input.entry.sha256,
        .bytes = input.entry.bytes,
    };
}

fn payload(
    arena: std.mem.Allocator,
    io: std.Io,
    dir: Dir,
    name: []const u8,
    large: bool,
) !content.ContainerRef {
    const bytes = try arena.alloc(u8, if (large) (2 << 20) + 17 else 17);
    @memset(bytes, if (large) 'A' else 'B');
    const tree = try content.fromEntries(arena, &.{
        .{ .path = "README.txt", .mode = 0o644, .body = content.Body.bytes(bytes) },
        .{ .path = "empty", .kind = .directory, .mode = 0o755 },
    }, .{});
    const file = try dir.createFile(io, name, .{ .exclusive = true });
    defer file.close(io);
    var buffer: [64 << 10]u8 = undefined; // SAFETY: writer owns the scratch buffer.
    var writer = file.writer(io, &buffer);
    const ref = try content.writeTar(arena, io, tree, &writer.interface, .{});
    try writer.interface.flush();
    try file.sync(io);
    return ref;
}
