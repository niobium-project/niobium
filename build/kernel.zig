//! Native kernel conformance and real-process recovery share the registered graph.
const std = @import("std");
const commands = @import("commands.zig");
const graph_mod = @import("graph.zig");

pub fn add(b: *std.Build, graph: graph_mod.Graph) *std.Build.Step {
    const step = commands.step(b, "test:kernel", "Native multi-root lifecycle and crash recovery");
    const imports = &.{ "kernel", "program", "content", "access", "platform" };
    const suite = b.addTest(
        .{
            .name = "kernel-native",
            .root_module = graph.root("tests/kernel/root.zig", imports),
        },
    );
    const native_run = b.addRunArtifact(suite);
    native_run.has_side_effects = true;
    step.dependOn(&native_run.step);
    addWireConformance(b, graph, step);
    const driver = b.addExecutable(
        .{
            .name = "kernel-driver",
            .root_module = graph.root("tests/kernel/driver.zig", imports),
        },
    );
    const provenance = graph.root("tests/aot/provenance.zig", &.{"core"});
    const main = graph.root("tests/kernel/main.zig", &.{"kernel"});
    main.addImport("suite_provenance", provenance);
    const witness = b.addExecutable(.{ .name = "kernel-acceptance", .root_module = main });
    const run = b.addRunArtifact(witness);
    run.addArtifactArg(driver);
    run.has_side_effects = true;
    step.dependOn(&run.step);
    return step;
}

fn addWireConformance(
    b: *std.Build,
    graph: graph_mod.Graph,
    kernel_step: *std.Build.Step,
) void {
    const module = graph.root("tests/kernel/wire_conformance.zig", &.{
        "kernel", "program", "access", "contracts",
    });
    const tests = b.addTest(.{ .name = "kernel-wire-contract", .root_module = module });
    kernel_step.dependOn(&b.addRunArtifact(tests).step);
    const executable = b.addExecutable(.{
        .name = "test:kernel-wire",
        .root_module = module,
    });
    const install = b.addInstallArtifact(executable, .{});
    const step = commands.step(
        b,
        "test:kernel-wire",
        "Build the read-only durable wire decoder witness",
    );
    step.dependOn(&install.step);
}
