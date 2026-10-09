//! Shared contract checks run on the build host independently of installer target selection.
const std = @import("std");
const graph_mod = @import("graph.zig");
const image = @import("image.zig");
const component = @import("component.zig");
const component_tools = @import("component_tools.zig");

pub fn add(
    b: *std.Build,
    inputs: graph_mod.Inputs,
    fetcher: *std.Build.Step.Compile,
    checker: *std.Build.Step.Compile,
) *std.Build.Step {
    @import("runtime_v2.zig").cross(b, inputs, checker);
    const step = b.step("core-test", "Content, access and compiler foundation conformance");
    step.dependOn(cpuSettings(b));
    const graph = graph_mod.create(b, .{
        .target = b.graph.host,
        .optimize = .safe,
        .inputs = inputs,
    });
    const authors = @import("author_v2.zig").add(b, &graph);
    const compiler = @import("compiler_v2.zig").add(b, inputs);
    step.dependOn(compiler.tests);
    step.dependOn(authors.tests);
    step.dependOn(@import("kernel.zig").add(b, graph));
    step.dependOn(@import("access.zig").add(b, &graph));
    unitSuites(b, &graph, step);
    step.dependOn(image.add(b, inputs));
    if (component_tools.supported(b.graph.host.result)) {
        const publication_graph = publicationGraph(b, inputs);
        const tools = component_tools.add(b, fetcher);
        const qualified = component.add(b, .{
            .publication = &publication_graph,
            .wasm_tools = tools.wasm_tools,
            .wit_bindgen = tools.wit_bindgen,
            .wasi_sysroot = tools.wasi_sysroot,
            .core = graph.get("core"),
            .program = graph.get("program"),
            .contracts = graph.get("contracts"),
        });
        authors.parity.addFileArg(qualified.reference_guest);
        const publication = @import("runtime_v2.zig").add(b, &graph, qualified.library, checker);
        const runtime = publication.runtime;
        step.dependOn(publication.binary_check);
        const signer = @import("signing.zig").add(b, fetcher);
        const metadata = @import("delivery_v2.zig").runtimePackage(b, compiler.compiler, runtime);
        sdk(b, publication, compiler.compiler, authors, qualified, signer, metadata);
        const product_inputs: @import("core_e2e.zig").Inputs = .{
            .runtime = runtime,
            .binary_check = publication.binary_check,
            .worker = qualified.caller,
            .compiler = compiler.compiler,
            .files = qualified.files_guest,
            .consumer = qualified.reference_guest,
            .consumer_v2 = qualified.reference_guest_v2,
            .metadata = metadata,
            .signer = signer.executable,
            .native_author = authors.native,
            .c_author = authors.c_author,
            .starlark = authors.starlark,
        };
        step.dependOn(@import("core_e2e.zig").add(b, &publication_graph, product_inputs));
        step.dependOn(@import("tutorial.zig").add(b, &graph, product_inputs));
        step.dependOn(&runtime.step);
        step.dependOn(qualified.step);
    } else {
        const missing = b.addFail("No published Component tool profile for this build host");
        step.dependOn(&missing.step);
        authors.tests.dependOn(&missing.step);
        b.step("component-test", "Component host qualification").dependOn(&missing.step);
        b.step("runtime-v2", "Complete Component runtime template").dependOn(&missing.step);
        b.step("core-e2e", "Delivered setup qualification").dependOn(&missing.step);
        b.step("core-sdk", "Publish the standard host SDK").dependOn(&missing.step);
        b.step("dsl-tutorial-test", "Execute tutorial authoring and installer lifecycle")
            .dependOn(&missing.step);
        b.step("dsl-tutorial-tools", "Build the DSL tutorial input preparation tool")
            .dependOn(&missing.step);
    }
    contentInterop(b, &graph, step);
    return step;
}

fn sdk(
    b: *std.Build,
    publication: @import("runtime_v2.zig").Publication,
    compiler: *std.Build.Step.Compile,
    authors: @import("author_v2.zig").Artifacts,
    qualified: component.Artifacts,
    signer: @import("signing.zig").Tool,
    metadata: std.Build.LazyPath,
) void {
    @import("delivery_v2.zig").add(b, .{
        .compiler = compiler,
        .runtime = publication.runtime,
        .binary_check = publication.binary_check,
        .worker = qualified.caller,
        .author_library = authors.library,
        .starlark = authors.starlark,
        .signer = signer,
        .files = qualified.files_guest,
        .consumer_v1 = qualified.reference_guest,
        .consumer_v2 = qualified.reference_guest_v2,
        .metadata = metadata,
        .cpu_provenance = qualified.cpu_provenance,
        .engine_build_log = qualified.engine_build_log,
    });
}

fn cpuSettings(b: *std.Build) *std.Build.Step {
    const suite = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/component_cpu.zig"),
            .target = b.graph.host,
            .optimize = .safe,
        }),
    });
    return &b.addRunArtifact(suite).step;
}

fn publicationGraph(b: *std.Build, inputs: graph_mod.Inputs) graph_mod.Graph {
    return graph_mod.create(b, .{
        .target = @import("publication.zig").baselineTarget(b),
        .optimize = .safe,
        .inputs = inputs,
    });
}

fn unitSuites(b: *std.Build, graph: *const graph_mod.Graph, step: *std.Build.Step) void {
    const runtime_inputs = b.addTest(.{
        .root_module = graph.root("apps/runtime-v2/product.zig", &.{
            "program", "contracts", "image", "content", "evaluator", "host_primitives", "access",
        }),
    });
    step.dependOn(&b.addRunArtifact(runtime_inputs).step);
    const argument_tests = b.addTest(.{
        .root_module = graph.root("apps/runtime-v2/arguments.zig", &.{
            "kernel", "program", "contracts",
        }),
    });
    step.dependOn(&b.addRunArtifact(argument_tests).step);
    for ([_][]const u8{
        "content",         "image",  "access",    "program", "compiler", "component_client",
        // Host and execution families remain separate test modules.
        "host_primitives", "kernel", "evaluator",
    }) |name| {
        const suite = b.addTest(.{ .name = name, .root_module = graph.get(name) });
        const run = b.addRunArtifact(suite);
        run.has_side_effects = true;
        step.dependOn(&run.step);
    }
}

fn contentInterop(b: *std.Build, graph: *const graph_mod.Graph, step: *std.Build.Step) void {
    const interop = b.addTest(.{
        .name = "content-interop",
        .root_module = graph.root("tests/content/root.zig", &.{"content"}),
    });
    const run = b.addRunArtifact(interop);
    run.has_side_effects = true;
    step.dependOn(&run.step);
    if (b.graph.host.result.os.tag != .windows) {
        const readers = b.addTest(.{
            .name = "content-readers",
            .root_module = graph.root("tests/content/readers.zig", &.{"content"}),
        });
        const readers_run = b.addRunArtifact(readers);
        readers_run.has_side_effects = true;
        step.dependOn(&readers_run.step);
    }
}
