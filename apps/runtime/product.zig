//! Resolve fixed members from the verified image; no filesystem library discovery.
const std = @import("std");
const image = @import("image");
const program = @import("program");
const content = @import("content");
const contracts = @import("contracts");
const evaluator = @import("evaluator");
const primitives = @import("host_primitives");
const Workspace = @import("workspace.zig").Workspace;
pub const Product = struct {
    file: std.Io.File,
    workspace: Workspace,
    model: program.model.Product,
    evaluator: evaluator.Context,

    pub fn open(
        arena: std.mem.Allocator,
        io: std.Io,
        original_path: []const u8,
        temporary: []const u8,
        loaded_slot: *const [image.descriptor.size]u8,
    ) !Product {
        const workspace = try Workspace.create(arena, io, temporary);
        errdefer workspace.deinit(io);
        const snapshot = try pin(arena, io, workspace.directory, original_path);
        const file = try workspace.directory.openFile(io, snapshot.name, .{});
        errdefer file.close(io);
        const source: content.Source = .{ .file = .{
            .handle = file,
            .length = (try file.stat(io)).size,
        } };
        const executable_sha256 = try evaluator.executable.hash(io, source);
        const descriptor = try image.verify(arena, io, source, .{});
        if (!std.meta.eql(descriptor, try image.descriptor.decode(loaded_slot)))
            return error.ExecutableChanged;
        const bytes = try readModel(arena, io, source, descriptor.program);
        const model = try program.model.decode(arena, bytes);
        const profile = primitives.runtimeProfile(try primitives.currentTarget());
        if (!std.mem.eql(u8, model.profile.id, profile.id)) return error.ProfileMismatch;
        try program.profile.require(profile, model.target, model.profile.primitives);
        const payload: content.Source = .{ .file = .{
            .handle = file,
            .offset = descriptor.payload.offset,
            .length = descriptor.payload.length,
        } };
        const tree = try content.parseTar(arena, io, payload, .{});
        const libraries = try arena.alloc(evaluator.Library, model.libraries.len);
        for (model.libraries, libraries) |library, *resolved| {
            const entry = try member(tree, library.member, library.bytes);
            resolved.* = .{ .id = library.id, .source = .{ .range = .{
                .path = snapshot.path,
                .offset = try std.math.add(u64, descriptor.payload.offset, entry.body.offset),
                .length = std.math.cast(u32, library.bytes) orelse return error.ProgramLimit,
                .sha256 = library.sha256,
            } } };
        }
        const containers = try arena.alloc(evaluator.Stored, model.containers.len);
        for (model.containers, containers) |container, *resolved| {
            const entry = try member(tree, container.member, container.reference.bytes);
            resolved.* = .{ .reference = container.reference, .body = entry.body };
        }
        return .{ .file = file, .workspace = workspace, .model = model, .evaluator = .{
            .executable = snapshot.path,
            .verified_executable = .{ .source = source, .sha256 = executable_sha256 },
            .libraries = libraries,
            .fixed_content = containers,
        } };
    }

    pub fn deinit(self: Product, io: std.Io) void {
        self.file.close(io);
        self.workspace.deinit(io);
    }
};

fn pin(
    arena: std.mem.Allocator,
    io: std.Io,
    workspace: std.Io.Dir,
    original_path: []const u8,
) !evaluator.executable.Snapshot {
    const file = try std.Io.Dir.cwd().openFile(io, original_path, .{ .follow_symlinks = false });
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.kind != .file) return error.ExecutableInvalid;
    const source: content.Source = .{ .file = .{ .handle = file, .length = stat.size } };
    return evaluator.executable.capture(arena, io, workspace, .{
        .source = source,
        .sha256 = try evaluator.executable.hash(io, source),
    }, null);
}

fn member(tree: content.Tree, path: []const u8, size: u64) !content.Entry {
    for (tree.entries) |entry| {
        if (!std.mem.eql(u8, entry.path, path)) continue;
        if (entry.kind != .file or entry.body.length != size) return error.ProductMemberInvalid;
        return entry;
    }
    return error.ProductMemberMissing;
}

fn readModel(
    arena: std.mem.Allocator,
    io: std.Io,
    source: content.Source,
    range: image.Range,
) ![]const u8 {
    if (range.length > contracts.limits.default.program_bytes) return error.ProgramLimit;
    const length = std.math.cast(usize, range.length) orelse return error.ProgramLimit;
    const bytes = try arena.alloc(u8, length);
    var offset: usize = 0;
    while (offset < bytes.len) {
        const end = offset + @min(bytes.len - offset, 64 << 10);
        try source.read(io, range.offset + offset, bytes[offset..end]);
        offset = end;
    }
    return bytes;
}

test "N2-RUNTIME-03: metadata reads use the captured image through A-B-A source changes" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const original = "{\"authority\":\"bounded\"}";
    try temp.dir.writeFile(io, .{ .sub_path = "source", .data = original });
    const path = try temp.dir.realPathFileAlloc(io, "source", a);
    const captured = try pin(a, io, temp.dir, path);
    defer captured.deinit(io);
    const file = try temp.dir.openFile(io, captured.name, .{});
    defer file.close(io);
    const source: content.Source = .{ .file = .{ .handle = file, .length = original.len } };
    try temp.dir.writeFile(io, .{ .sub_path = "source", .data = "{\"authority\":\"forged\"}" });
    const during = try readModel(a, io, source, .{ .offset = 0, .length = original.len });
    try std.testing.expectEqualStrings(original, during);
    try temp.dir.writeFile(io, .{ .sub_path = "source", .data = original });
    const after = try readModel(a, io, source, .{ .offset = 0, .length = original.len });
    try std.testing.expectEqualStrings(original, after);
}
