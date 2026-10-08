//! Runtime template release builds precede byte-only product assembly qualification.

const std = @import("std");
const graph_mod = @import("graph.zig");

pub fn add(b: *std.Build, inputs: graph_mod.Inputs) *std.Build.Step {
    const step = b.step("image-test", "Native image assembly and target-host execution");
    const host = graph_mod.create(b, .{
        .target = b.graph.host,
        .optimize = .safe,
        .inputs = inputs,
    });
    const checker = b.addExecutable(.{
        .name = "image-qualification",
        .root_module = host.root("tests/image/check.zig", &.{ "image", "core" }),
    });
    const run = b.addRunArtifact(checker);
    run.has_side_effects = true;
    run.setCwd(b.path("."));
    const queries = [_]std.Target.Query{
        .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    };
    for (queries, 0..) |query, index| {
        const graph = graph_mod.create(b, .{
            .target = b.resolveTargetQuery(query),
            .optimize = .safe,
            .inputs = inputs,
        });
        const runtime = b.addExecutable(.{
            .name = b.fmt("image-runtime-{d}", .{index}),
            .root_module = graph.root("tests/image/runtime.zig", &.{"image"}),
        });
        run.addArtifactArg(runtime);
    }
    step.dependOn(&run.step);
    return step;
}
