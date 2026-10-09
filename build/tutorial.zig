//! Runnable examples use the same published bytes as the consumable core SDK.
const std = @import("std");
const commands = @import("commands.zig");
const graph_mod = @import("graph.zig");
const Inputs = @import("core_e2e.zig").Inputs;

pub fn add(b: *std.Build, graph: *const graph_mod.Graph, inputs: Inputs) *std.Build.Step {
    const prepare = b.addExecutable(.{
        .name = "niobium-tutorial-prepare",
        .root_module = graph.root("examples/dsl-tutorial/prepare.zig", &.{
            "compiler", "content", "contracts",
        }),
    });
    commands.step(b, "example:tutorial:tools", "Build the DSL tutorial input preparation tool")
        .dependOn(&b.addInstallArtifact(prepare, .{}).step);
    const unit = b.addTest(.{ .root_module = prepare.root_module });
    const sdk = b.addWriteFiles();
    const suffix = if (b.graph.host.result.os.tag == .windows) ".exe" else "";
    const staged = [_]std.Build.LazyPath{
        sdk.addCopyFile(
            inputs.runtime.getEmittedBin(),
            b.fmt("bin/niobium-runtime-v2{s}", .{suffix}),
        ),
        sdk.addCopyFile(
            inputs.worker.getEmittedBin(),
            b.fmt("bin/niobium-component-worker{s}", .{suffix}),
        ),
        sdk.addCopyFile(inputs.metadata, "share/niobium/runtime-package.json"),
        sdk.addCopyFile(inputs.files, "lib/niobium/stdlib/files.wasm"),
        sdk.addCopyFile(inputs.signer, b.fmt("bin/rcodesign{s}", .{suffix})),
    };
    const module = graph.root("tests/dsl_tutorial/main.zig", &.{
        "compiler", "program", "kernel", "image", "contracts",
    });
    module.addImport("suite_provenance", graph.root("tests/aot/provenance.zig", &.{"core"}));
    const suite = b.addExecutable(.{ .name = "example-tutorial", .root_module = module });
    const run = b.addRunArtifact(suite);
    run.setCwd(b.path("."));
    run.has_side_effects = true;
    for (staged) |file| run.addFileInput(file);
    run.addArtifactArg(prepare);
    run.addArtifactArg(inputs.compiler);
    run.addFileArg(inputs.starlark);
    run.addDirectoryArg(sdk.getDirectory());
    run.addDirectoryArg(b.path("examples/dsl-tutorial"));
    for ([_][]const u8{
        "product.star",       "product_modular.star", "model.star", "product_flow.star",
        "payload/README.txt", "fallback/README.txt",
    }) |path| run.addFileInput(b.path(b.fmt("examples/dsl-tutorial/{s}", .{path})));
    const step = commands.step(
        b,
        "example:tutorial",
        "Execute tutorial authoring and installer lifecycle",
    );
    step.dependOn(inputs.binary_check);
    step.dependOn(&b.addRunArtifact(unit).step);
    step.dependOn(&run.step);
    return step;
}
