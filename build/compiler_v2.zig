//! The product compiler runs on the build host and consumes separately published runtimes.

const std = @import("std");
const commands = @import("commands.zig");
const graph_mod = @import("graph.zig");

pub const Artifacts = struct { compiler: *std.Build.Step.Compile, tests: *std.Build.Step };

pub fn add(b: *std.Build, inputs: graph_mod.Inputs) Artifacts {
    const graph = graph_mod.create(b, .{
        .target = @import("publication.zig").baselineTarget(b),
        .optimize = .safe,
        .inputs = inputs,
    });
    const imports = &.{
        "compiler",        "program",          "contracts", "content", "image", "access",
        "host_primitives", "component_client",
    };
    const compiler = b.addExecutable(.{
        .name = "niobium-compiler-v2",
        .root_module = graph.root("apps/compiler-v2/main.zig", imports),
    });
    const install = b.addInstallArtifact(compiler, .{});
    const step = commands.step(
        b,
        "compiler:build",
        "Build the host compiler for standard Component products",
    );
    step.dependOn(&install.step);
    const suite = b.addTest(.{ .root_module = graph.root("apps/compiler-v2/main.zig", imports) });
    const tests = commands.step(b, "test:compiler", "Host compiler argument and adapter checks");
    tests.dependOn(&b.addRunArtifact(suite).step);
    addLinux(b, inputs);
    return .{ .compiler = compiler, .tests = tests };
}

fn addLinux(b: *std.Build, inputs: graph_mod.Inputs) void {
    const graph = graph_mod.create(b, .{
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .cpu_model = .baseline,
            .os_tag = .linux,
            .abi = .musl,
        }),
        .optimize = .safe,
        .inputs = inputs,
    });
    const compiler = b.addExecutable(.{
        .name = "niobium-compiler-v2-linux-x64",
        .root_module = graph.root("apps/compiler-v2/main.zig", &.{
            "compiler",        "program",          "contracts", "content", "image", "access",
            "host_primitives", "component_client",
        }),
    });
    const install = b.addInstallArtifact(compiler, .{});
    const step = commands.step(
        b,
        "compiler:linux-x64",
        "Build the Linux x64 host compiler without an engine",
    );
    step.dependOn(&install.step);
}
