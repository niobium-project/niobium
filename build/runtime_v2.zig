//! Published runtime build. Product assembly depends on its emitted bytes only.
const std = @import("std");
const graph_mod = @import("graph.zig");
const component = @import("component.zig");
pub const Publication = struct {
    runtime: *std.Build.Step.Compile,
    binary_check: *std.Build.Step,
};

pub fn add(
    b: *std.Build,
    graph: *const graph_mod.Graph,
    library: std.Build.LazyPath,
    checker: *std.Build.Step.Compile,
) Publication {
    const publication = graph_mod.create(b, .{
        .target = @import("publication.zig").baselineTarget(b),
        .optimize = .safe,
        .inputs = graph.config.inputs,
    });
    const runtime = executable(b, &publication, library, "niobium-runtime-v2");
    const binary_check = checkBinary(b, runtime, checker);
    const step = b.step("runtime-v2", "Build the complete Component runtime template");
    step.dependOn(&b.addInstallArtifact(runtime, .{}).step);
    step.dependOn(binary_check);
    return .{ .runtime = runtime, .binary_check = binary_check };
}

fn checkBinary(
    b: *std.Build,
    runtime: *std.Build.Step.Compile,
    checker: *std.Build.Step.Compile,
) *std.Build.Step {
    const target = runtime.root_module.resolved_target.?.result;
    const selector = if (target.os.tag == .macos)
        b.fmt("{s}-macos", .{@tagName(target.cpu.arch)})
    else
        b.fmt("{s}-{s}-{s}", .{
            @tagName(target.cpu.arch), @tagName(target.os.tag), @tagName(target.abi),
        });
    const run = b.addRunArtifact(checker);
    run.addArgs(&.{ "lint", "--profile", "component", "--target", selector, "--kind", "exe" });
    run.addArtifactArg(runtime);
    run.has_side_effects = true;
    const size = b.addRunArtifact(checker);
    size.setCwd(b.path("."));
    size.addArgs(&.{
        "size", "--baseline", "tools/size-gate/component-baseline.zon", "--limit", "31457280",
    });
    size.addArg(selector);
    size.addArtifactArg(runtime);
    size.addFileInput(b.path("tools/size-gate/component-baseline.zon"));
    size.has_side_effects = true;
    run.step.dependOn(&size.step);
    return &run.step;
}

fn executable(
    b: *std.Build,
    graph: *const graph_mod.Graph,
    library: std.Build.LazyPath,
    name: []const u8,
) *std.Build.Step.Compile {
    const engine = graph.get("component_engine");
    engine.addObjectFile(library);
    component.attachNative(engine);
    const module = graph.get("runtime_process");
    module.strip = true;
    const binary = b.addExecutable(.{ .name = name, .root_module = module });
    if (graph.config.target.result.os.tag == .windows) addWindowsManifest(b, binary);
    return binary;
}

fn addWindowsManifest(b: *std.Build, binary: *std.Build.Step.Compile) void {
    const rc = b.addSystemCommand(&.{
        b.graph.zig_exe, "rc", "/:no-preprocess", "/:auto-includes", "none", "/i",
    });
    rc.addDirectoryArg(b.path("apps/runtime-v2"));
    rc.addArg("/fo");
    const object = rc.addOutputFileArg("runtime.res");
    rc.addArg("--");
    rc.addFileArg(b.path("apps/runtime-v2/runtime.rc"));
    rc.addFileInput(b.path("apps/runtime-v2/runtime.manifest"));
    binary.root_module.addObjectFile(object);
}

/// Runtime publishers supply the pinned engine built for each target. Product builds use templates.
pub fn cross(
    b: *std.Build,
    inputs: graph_mod.Inputs,
    checker: *std.Build.Step.Compile,
) void {
    const targets = .{
        .{
            "linux-x64",
            std.Target.Query{
                .cpu_arch = .x86_64,
                .cpu_model = .baseline,
                .os_tag = .linux,
                .abi = .musl,
            },
        },
        .{
            "windows-x64",
            std.Target.Query{
                .cpu_arch = .x86_64,
                .cpu_model = .baseline,
                .os_tag = .windows,
                .abi = .gnu,
            },
        },
    };
    inline for (targets) |target| {
        const option = "component-library-" ++ target[0];
        const step = b.step("runtime-" ++ target[0], "Build a complete target runtime template");
        if (b.option([]const u8, option, "Pinned target Wasmtime static library")) |path| {
            const graph = graph_mod.create(b, .{
                .target = b.resolveTargetQuery(target[1]),
                .optimize = .safe,
                .inputs = inputs,
            });
            const binary = executable(
                b,
                &graph,
                .{ .cwd_relative = path },
                "niobium-runtime-v2-" ++ target[0],
            );
            step.dependOn(&b.addInstallArtifact(binary, .{}).step);
            step.dependOn(checkBinary(b, binary, checker));
            const worker = b.addExecutable(.{
                .name = "niobium-component-worker-" ++ target[0],
                .root_module = graph.root("apps/component-worker/main.zig", &.{"component_worker"}),
            });
            step.dependOn(&b.addInstallArtifact(worker, .{}).step);
        } else {
            const missing = b.addFail("Provide -D" ++ option ++ "=<pinned target static library>");
            step.dependOn(&missing.step);
        }
    }
}
