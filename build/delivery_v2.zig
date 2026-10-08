//! The consumable host SDK and complete runtime are published separately from product assembly.
const std = @import("std");
pub const Inputs = struct {
    compiler: *std.Build.Step.Compile,
    runtime: *std.Build.Step.Compile,
    worker: *std.Build.Step.Compile,
    author_library: *std.Build.Step.Compile,
    starlark: std.Build.LazyPath,
    signer: @import("signing.zig").Tool,
    files: std.Build.LazyPath,
    consumer_v1: std.Build.LazyPath,
    consumer_v2: std.Build.LazyPath,
};

pub fn add(b: *std.Build, inputs: Inputs) void {
    const step = b.step(
        "core-sdk",
        "Publish the host compiler/SDK and precompiled runtime profile",
    );
    for ([_]*std.Build.Step.Compile{
        inputs.compiler, inputs.runtime, inputs.worker, inputs.author_library,
    }) |artifact| step.dependOn(&b.addInstallArtifact(artifact, .{}).step);
    const suffix = if (b.graph.host.result.os.tag == .windows) ".exe" else "";
    step.dependOn(
        &b.addInstallBinFile(inputs.starlark, b.fmt("niobium-starlark-v2{s}", .{suffix})).step,
    );
    step.dependOn(
        &b.addInstallBinFile(inputs.signer.executable, b.fmt("rcodesign{s}", .{suffix})).step,
    );
    step.dependOn(
        &b.addInstallFile(inputs.signer.notice, "share/niobium/licenses/apple-codesign.txt").step,
    );
    step.dependOn(&b.addInstallFile(b.path("api/c/compiler_v2.h"), "include/compiler_v2.h").step);
    step.dependOn(
        &b.addInstallFile(
            b.path("api/wit/runtime/proposal.wit"),
            "share/niobium/wit/runtime/proposal.wit",
        ).step,
    );
    step.dependOn(
        &b.addInstallFile(
            b.path("api/wit/files/files.wit"),
            "share/niobium/wit/files/files.wit",
        ).step,
    );
    step.dependOn(&b.addInstallFile(inputs.files, "lib/niobium/stdlib/files.wasm").step);
    step.dependOn(
        &b.addInstallFile(inputs.consumer_v1, "share/niobium/examples/toolchain-v1.wasm").step,
    );
    step.dependOn(
        &b.addInstallFile(inputs.consumer_v2, "share/niobium/examples/toolchain-v2.wasm").step,
    );
    const publish = b.addRunArtifact(inputs.compiler);
    publish.addArgs(&.{ "runtime-package", "--template" });
    publish.addArtifactArg(inputs.runtime);
    publish.addArgs(&.{ "--target", b.fmt("{s}-{s}", .{
        @tagName(b.graph.host.result.cpu.arch), @tagName(b.graph.host.result.os.tag),
    }), "--version", "0.3.0-dev", "--out" });
    step.dependOn(
        &b.addInstallFile(
            publish.addOutputFileArg("runtime-package.json"),
            "share/niobium/runtime-package.json",
        ).step,
    );
}
