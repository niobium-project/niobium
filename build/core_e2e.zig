//! Final bytes, fixed library dataflow and native lifecycle acceptance.
const std = @import("std");
const commands = @import("commands.zig");
const graph_mod = @import("graph.zig");
pub const Inputs = struct {
    runtime: *std.Build.Step.Compile,
    binary_check: *std.Build.Step,
    worker: *std.Build.Step.Compile,
    compiler: *std.Build.Step.Compile,
    files: std.Build.LazyPath,
    consumer: std.Build.LazyPath,
    consumer_v2: std.Build.LazyPath,
    signer: std.Build.LazyPath,
    native_author: *std.Build.Step.Compile,
    c_author: *std.Build.Step.Compile,
    starlark: std.Build.LazyPath,
    metadata: std.Build.LazyPath,
};

pub fn add(b: *std.Build, graph: *const graph_mod.Graph, inputs: Inputs) *std.Build.Step {
    crossTools(b, graph);
    const module = graph.root("tests/core_e2e/main.zig", &.{
        "compiler", "program", "content", "host_primitives", "image", "kernel",
    });
    module.addImport("suite_provenance", graph.root("tests/component/provenance.zig", &.{"core"}));
    const suite = b.addExecutable(.{ .name = "core-e2e", .root_module = module });
    const run = b.addRunArtifact(suite);
    run.setCwd(b.path("."));
    run.has_side_effects = true;
    run.addArtifactArg(inputs.runtime);
    run.addArtifactArg(inputs.worker);
    run.addFileArg(inputs.files);
    run.addFileArg(inputs.consumer);
    run.addArtifactArg(inputs.compiler);
    run.addFileArg(inputs.signer);
    run.addArtifactArg(inputs.native_author);
    run.addArtifactArg(inputs.c_author);
    run.addFileArg(inputs.starlark);
    run.addFileArg(b.path("tests/author/author.star"));
    run.addFileArg(inputs.consumer_v2);
    run.addFileArg(inputs.metadata);
    run.addFileInput(b.path("tests/author/types.star"));
    const step = commands.step(
        b,
        "core:e2e",
        "Delivered setup lifecycle, content and migration acceptance",
    );
    step.dependOn(inputs.binary_check);
    step.dependOn(&run.step);
    return step;
}

fn crossTools(b: *std.Build, graph: *const graph_mod.Graph) void {
    const cross = graph_mod.create(b, .{
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .cpu_model = .baseline,
            .os_tag = .linux,
            .abi = .musl,
        }),
        .optimize = .safe,
        .inputs = graph.config.inputs,
    });
    const prepare = b.addExecutable(.{
        .name = "core-cross-prepare",
        .root_module = graph.root("tests/core_e2e/cross_prepare.zig", &.{
            "compiler", "program", "content", "host_primitives",
        }),
    });
    const assemble = b.addExecutable(.{
        .name = "core-cross-assemble",
        .root_module = cross.root("tests/core_e2e/cross_assemble.zig", &.{
            "compiler", "program", "image",
        }),
    });
    const step = commands.step(
        b,
        "core:cross-tools",
        "Build isolated Linux cross-assembly acceptance tools",
    );
    step.dependOn(&b.addInstallArtifact(prepare, .{}).step);
    step.dependOn(&b.addInstallArtifact(assemble, .{}).step);
    delivered(b, graph, "native", step);
    delivered(b, &cross, "linux-x64", step);
    const windows = graph_mod.create(b, .{
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .cpu_model = .baseline,
            .os_tag = .windows,
            .abi = .gnu,
        }),
        .optimize = .safe,
        .inputs = graph.config.inputs,
    });
    delivered(b, &windows, "windows-x64", step);
}

fn delivered(
    b: *std.Build,
    graph: *const graph_mod.Graph,
    name: []const u8,
    step: *std.Build.Step,
) void {
    const module = graph.root("tests/core_e2e/delivered.zig", &.{
        "compiler", "program", "content", "host_primitives", "image", "kernel",
    });
    module.addImport("suite_provenance", graph.root("tests/component/provenance.zig", &.{"core"}));
    const artifact = b.addExecutable(.{
        .name = b.fmt("core-delivered-{s}", .{name}),
        .root_module = module,
    });
    step.dependOn(&b.addInstallArtifact(artifact, .{}).step);
}
