//! Standalone assembler consumer. Its inputs are precompiled files, with no runtime sources.

const std = @import("std");
const image = @import("image");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);
    if (argv.len == 2) return inspect(init, argv[1]);
    if (argv.len == 3 and std.mem.eql(u8, argv[1], "verify-signature")) {
        const file = try std.Io.Dir.cwd().openFile(init.io, argv[2], .{});
        defer file.close(init.io);
        try image.verifyAdhoc(arena, init.io, .{ .file = .{
            .handle = file,
            .length = (try file.stat(init.io)).size,
        } }, .{});
        return std.Io.File.stdout().writeStreamingAll(init.io, "ADHOC_MEASUREMENTS_OK\n");
    }
    if (argv.len != 4) return error.Usage;
    const template = try std.Io.Dir.cwd().openFile(init.io, argv[1], .{});
    defer template.close(init.io);
    const payload = try std.Io.Dir.cwd().openFile(init.io, argv[2], .{});
    defer payload.close(init.io);
    const output = try std.Io.Dir.cwd().createFile(init.io, argv[3], .{
        .exclusive = true,
        .read = true,
    });
    defer output.close(init.io);
    const payload_size = (try payload.stat(init.io)).size;
    const result = try image.assemble(arena, init.io, .{ .file = .{
        .handle = template,
        .length = (try template.stat(init.io)).size,
    } }, .bytes("NIOBIUM_IMAGE_V2_OK"), .{
        .source = .{ .file = .{ .handle = payload, .length = payload_size } },
        .length = payload_size,
    }, output, .{});
    if (std.Io.File.Permissions.has_executable_bit) {
        try output.setPermissions(init.io, .fromMode(0o755));
    }
    try output.sync(init.io);
    const report = try std.json.Stringify.valueAlloc(arena, result, .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, report);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}

fn inspect(init: std.process.Init, path: []const u8) !void {
    const arena = init.arena.allocator();
    const file = try std.Io.Dir.cwd().openFile(init.io, path, .{});
    defer file.close(init.io);
    const source: image.Source = .{ .file = .{
        .handle = file,
        .length = (try file.stat(init.io)).size,
    } };
    const layout = try image.native.inspect(arena, init.io, source, .{});
    const product = image.verify(arena, init.io, source, .{}) catch |err| switch (err) {
        error.ImageMissing => null,
        else => return err,
    };
    const report = try std.json.Stringify.valueAlloc(arena, .{
        .format = layout.format,
        .cpu = layout.cpu,
        .code = layout.code,
        .product = product,
    }, .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, report);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
