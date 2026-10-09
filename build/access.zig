//! Native permission verification belongs to the actual verify dependency graph.
const std = @import("std");
const graph_mod = @import("graph.zig");

pub fn add(b: *std.Build, graph: *const graph_mod.Graph) *std.Build.Step {
    const module = graph.root("tests/access/root.zig", &.{"access"});
    module.link_libc = true;
    module.addCSourceFile(.{
        .file = b.path("tests/access/native.c"),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" },
    });
    const suite = b.addTest(.{ .name = "access-native", .root_module = module });
    const run = b.addRunArtifact(suite);
    run.has_side_effects = true;
    const step = b.step("access-test", "Native permission effects, receipts and restoration");
    step.dependOn(&run.step);
    return step;
}
