//! Native PoC delivery and conformance consume prebuilt runtime artifacts at product assembly.

const std = @import("std");
const graph_mod = @import("graph.zig");
const authoring = @import("compiler.zig");
const wamr = @import("wamr.zig");

pub fn add(
    b: *std.Build,
    inputs: graph_mod.Inputs,
    check_binary: *std.Build.Step.Compile,
) ?*std.Build.Step {
    const artifacts = b.step("aot", "Build compiler, runtime and capability libraries");
    const tests = b.step("aot-test", "Authoring, sandbox and frozen-plan conformance");
    const e2e = b.step("aot-e2e", "Native DSL/AOT product, migration and crash-recovery evidence");
    const target = b.graph.host;
    if (target.result.os.tag != .macos or target.result.cpu.arch != .aarch64) {
        const unsupported = b.addFail("DSL/AOT PoC requires a macOS arm64 build host");
        artifacts.dependOn(&unsupported.step);
        tests.dependOn(&unsupported.step);
        e2e.dependOn(&unsupported.step);
        return null;
    }
    const graph = graph_mod.create(b, .{
        .target = target,
        .optimize = .safe,
        .inputs = inputs,
    });
    const tools = authoring.add(b, &graph);
    const runtime_module = graph.root("apps/runtime/main.zig", &.{
        "runtime", "program", "contracts",
    });
    runtime_module.link_libc = true;
    const runtime = b.addExecutable(.{ .name = "niobium-runtime", .root_module = runtime_module });
    const binary_check = b.addRunArtifact(check_binary);
    binary_check.addArgs(&.{ "lint", "--target", "aarch64-macos", "--kind", "exe" });
    binary_check.addFileArg(runtime.getEmittedBin());
    tests.dependOn(&binary_check.step);
    addSizeGate(b, runtime, check_binary, tests);
    for ([_]*std.Build.Step.Compile{
        runtime, tools.compiler, tools.library, tools.author_zig, tools.author_c,
    }) |artifact| artifacts.dependOn(&b.addInstallArtifact(artifact, .{}).step);
    artifacts.dependOn(&b.addInstallBinFile(tools.starlark, "niobium-starlark").step);
    artifacts.dependOn(&b.addInstallFile(b.path("api/c/compiler.h"), "include/compiler.h").step);
    const capability_header = b.addInstallFile(
        b.path("api/c/capability.h"),
        "include/capability.h",
    );
    artifacts.dependOn(&capability_header.step);
    const libraries = guests(b, artifacts);
    addTests(b, &graph, tests, tools.tests);
    const suite_module = graph.root("tests/aot/main.zig", &.{
        "core", "program", "contracts", "compiler", "runtime",
    });
    suite_module.link_libc = true;
    const suite = b.addExecutable(.{
        .name = "niobium-aot-e2e",
        .root_module = suite_module,
    });
    const run = b.addRunArtifact(suite);
    run.setCwd(b.path("."));
    run.has_side_effects = true;
    const executables = [_]*std.Build.Step.Compile{
        runtime, tools.compiler, tools.author_zig, tools.author_c,
    };
    for (executables) |exe| {
        run.addArtifactArg(exe);
    }
    run.addFileArg(tools.starlark);
    run.addFileArg(b.path("examples/aot/toolchain.star"));
    for (libraries) |library| run.addArtifactArg(library);
    run.addArtifactArg(check_binary);
    e2e.dependOn(tests);
    e2e.dependOn(&run.step);
    return e2e;
}

fn guests(b: *std.Build, install: *std.Build.Step) [3]*std.Build.Step.Compile {
    const result = [_]*std.Build.Step.Compile{
        wamr.guest(b, "managed", "examples/aot-libraries/managed-files.c", &.{}),
        wamr.guest(b, "env-v1", "examples/aot-libraries/generated-env.c", &.{"-DENV_VERSION=1"}),
        wamr.guest(b, "env-v2", "examples/aot-libraries/generated-env.c", &.{"-DENV_VERSION=2"}),
    };
    for (result) |library| {
        const path = b.fmt("lib/capabilities/{s}.wasm", .{library.name});
        install.dependOn(&b.addInstallFile(library.getEmittedBin(), path).step);
    }
    return result;
}

fn addSizeGate(
    b: *std.Build,
    runtime: *std.Build.Step.Compile,
    checker: *std.Build.Step.Compile,
    tests: *std.Build.Step,
) void {
    const step = b.step("aot-size", "Precompiled runtime size and growth budget");
    const run = b.addRunArtifact(checker);
    run.setCwd(b.path("."));
    run.addArgs(&.{
        "size",          "--baseline", "tools/size-gate/aot-baseline.zon", "--limit", "31457280",
        "aarch64-macos",
    });
    run.addFileArg(runtime.getEmittedBin());
    run.addPassthruArgs();
    run.has_side_effects = true;
    step.dependOn(&run.step);
    tests.dependOn(&run.step);
}

fn addTests(
    b: *std.Build,
    graph: *const graph_mod.Graph,
    step: *std.Build.Step,
    frontend_tests: *std.Build.Step,
) void {
    step.dependOn(frontend_tests);
    const module = graph.root("libs/wasm_host/tests.zig", &.{ "wasm_host", "contracts" });
    module.addImport("fixtures", wamr.fixtures(b));
    const sandbox = b.addTest(.{ .name = "capability-conformance", .root_module = module });
    const sandbox_run = b.addRunArtifact(sandbox);
    sandbox_run.has_side_effects = true;
    step.dependOn(&sandbox_run.step);
    const schema = b.addTest(.{
        .name = "schema-conformance",
        .root_module = graph.root("tests/aot/schema.zig", &.{ "program", "runtime" }),
    });
    const schema_run = b.addRunArtifact(schema);
    schema_run.setCwd(b.path("."));
    for ([_][]const u8{
        "compiled-program-v1.schema.json",
        "runtime-state-v1.schema.json",
        "runtime-plan-v1.schema.json",
    }) |name| schema_run.addFileInput(b.path(b.fmt("api/schema/{s}", .{name})));
    step.dependOn(&schema_run.step);
    const modules = [_][]const u8{
        "program", "compiler", "wasm_profile", "runtime", "capability_sdk",
    };
    for (modules) |name| {
        const suite = b.addTest(.{ .name = name, .root_module = graph.get(name) });
        const run = b.addRunArtifact(suite);
        if (std.mem.eql(u8, name, "runtime")) run.has_side_effects = true;
        step.dependOn(&run.step);
    }
}
