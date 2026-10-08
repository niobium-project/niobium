//! Real-process AOT qualification. Arguments are prebuilt tools, never source compilers.

const std = @import("std");
const World = @import("world.zig").World;
const authoring = @import("authoring.zig");
const packaging = @import("packaging.zig");
const lifecycle = @import("lifecycle.zig");
const recovery = @import("recovery.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var world = try World.init(init, args);
    execute(&world) catch |err| {
        try world.write(try world.path("summary.json"), try std.json.Stringify.valueAlloc(
            world.arena,
            .{ .status = "FAIL", .failure = @errorName(err) },
            .{},
        ));
        std.log.err("AOT acceptance failed: {s}; evidence {s}", .{
            @errorName(err), world.evidence,
        });
        return err;
    };
    try world.write(try world.path("summary.json"), "{\"status\":\"PASS\"}\n");
    std.log.info("AOT acceptance PASS: {s}", .{world.evidence});
}

fn execute(w: *World) !void {
    const programs = try authoring.verify(w.arena, w.io, .{
        .author_zig = w.tools.author_zig,
        .author_c = w.tools.author_c,
        .starlark = w.tools.starlark,
        .source = w.tools.source,
        .library_v1 = w.tools.env_v1,
        .library_v2 = w.tools.env_v2,
        .output_dir = try w.path("authoring"),
    });
    try w.case("N2-AUTH-01", "three-frontends", "PASS");
    const setups = try packaging.build(w, programs);
    try lifecycle.verify(w, setups);
    try recovery.verify(w, setups);
    try w.case("N2-SAFE-01", "guest-conformance-in-separate-aot-wasm-test", "NOT_RUN");
}
