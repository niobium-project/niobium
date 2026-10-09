//! Local entry for the tutorial. The tools link the repository module graph, so
//! these steps call the root `example:tutorial` steps rather than rebuilding it.

const std = @import("std");

pub fn build(b: *std.Build) void {
    delegate(b, "tools", "example:tutorial:tools", "Build the tutorial preparation tool");
    delegate(b, "test", "example:tutorial", "Run the tutorial lifecycle checks");
}

fn delegate(
    b: *std.Build,
    name: []const u8,
    root_step: []const u8,
    description: []const u8,
) void {
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build", root_step });
    run.setCwd(b.path("../.."));
    run.has_side_effects = true;
    b.step(name, description).dependOn(&run.step);
}
