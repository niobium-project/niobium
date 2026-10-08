//! Run on the author host, then expose only these published files to Linux assembly.
const std = @import("std");
const program = @import("program");
const prepare = @import("prepare.zig");
const Dir = std.Io.Dir;

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 12) return error.Usage;
    const base = args[1];
    try Dir.cwd().createDir(init.io, base, .default_dir);
    const dir = try Dir.cwd().openDir(init.io, base, .{});
    defer dir.close(init.io);
    try Dir.cwd().copyFile(args[2], dir, "compiler", init.io, .{ .permissions = .executable_file });
    try Dir.cwd().copyFile(
        args[11],
        dir,
        "assemble",
        init.io,
        .{ .permissions = .executable_file },
    );
    const targets = [_]program.profile.Target{
        .@"aarch64-macos", .@"x86_64-windows", .@"x86_64-linux",
    };
    for (targets, 0..) |target, index| {
        const path = try std.fs.path.join(a, &.{ base, @tagName(target) });
        const inputs = try prepare.create(a, init.io, path, target, .{
            .runtime = args[index + 3],
            .worker = args[6],
            .signer = args[7],
            .files = args[8],
            .consumer = args[9],
        });
        try prepare.models(a, init.io, inputs, target);
        const upgrade = try std.fs.path.join(a, &.{ path, "upgrade" });
        const newer = try prepare.create(a, init.io, upgrade, target, .{
            .runtime = args[index + 3],
            .worker = args[6],
            .signer = args[7],
            .files = args[8],
            .consumer = args[10],
        });
        try prepare.models(a, init.io, newer, target);
    }
}
