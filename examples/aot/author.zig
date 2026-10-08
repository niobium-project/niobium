//! Equivalent native author for toolchain.star and author.c.

const std = @import("std");
const compiler = @import("compiler");
const contracts = @import("contracts");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 4) return error.Usage;
    const version = try std.fmt.parseInt(u32, args[3], 10);
    if (version != 1 and version != 2) return error.Usage;
    const wasm = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], arena, .limited(
        (contracts.Limits{}).wasm_module_bytes,
    ));
    var author = try compiler.Builder.init(arena, "example.toolchain", version, version);
    try author.addLibrary("environment", wasm);
    try author.addInput("sdk", "stable");
    try author.addResource("environment", "toolchain.env");
    try author.addInstance("environment", "environment", version);
    try author.bind("environment", .input, "sdk");
    try author.bind("environment", .resource, "environment");
    if (version == 2) {
        for ([_][]const u8{ "", "environment" }) |owner| {
            try author.addMigration(owner, "upgrade-1-2", 1, 2);
        }
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = args[2],
        .data = try author.emit(),
        .flags = .{ .exclusive = true },
    });
}
