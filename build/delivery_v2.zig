//! The consumable host SDK and complete runtime are published separately from product assembly.
const std = @import("std");
pub const Inputs = struct {
    compiler: *std.Build.Step.Compile,
    runtime: *std.Build.Step.Compile,
    binary_check: *std.Build.Step,
    worker: *std.Build.Step.Compile,
    author_library: *std.Build.Step.Compile,
    starlark: std.Build.LazyPath,
    signer: @import("signing.zig").Tool,
    files: std.Build.LazyPath,
    consumer_v1: std.Build.LazyPath,
    consumer_v2: std.Build.LazyPath,
    metadata: std.Build.LazyPath,
    cpu_provenance: std.Build.LazyPath,
    engine_build_log: std.Build.LazyPath,
};

pub fn add(b: *std.Build, inputs: Inputs) void {
    const step = b.step(
        "core-sdk",
        "Publish the host compiler/SDK and precompiled runtime profile",
    );
    step.dependOn(inputs.binary_check);
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
    step.dependOn(&b.addInstallFile(
        inputs.cpu_provenance,
        "share/niobium/provenance/cpu.json",
    ).step);
    step.dependOn(&b.addInstallFile(
        inputs.engine_build_log,
        "share/niobium/provenance/engine-build.log",
    ).step);
    step.dependOn(&b.addInstallFile(
        inputs.metadata,
        "share/niobium/runtime-package.json",
    ).step);
}

pub fn runtimePackage(
    b: *std.Build,
    compiler: *std.Build.Step.Compile,
    runtime: *std.Build.Step.Compile,
) std.Build.LazyPath {
    const publish = b.addRunArtifact(compiler);
    const profile = @import("publication.zig").nativeProfile(
        runtime.root_module.resolved_target.?.result,
    ) catch invalid: {
        publish.step.dependOn(&b.addFail("Unqualified native CPU/ABI publication profile").step);
        break :invalid "unqualified";
    };
    publish.addArgs(&.{ "runtime-package", "--template" });
    publish.addArtifactArg(runtime);
    publish.addArgs(&.{ "--native-profile", profile, "--target", b.fmt("{s}-{s}", .{
        @tagName(b.graph.host.result.cpu.arch), @tagName(b.graph.host.result.os.tag),
    }), "--version", "0.3.0-dev", "--out" });
    return publish.addOutputFileArg("runtime-package.json");
}
