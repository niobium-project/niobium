//! Thin entry. Module graph: build/modules.zig. Steps: build/steps/*.zig. The `pub` functions
//! below are the build API for products that depend on Niobium (docs/development/consuming.md).

const std = @import("std");
const commands = @import("build/commands.zig");
const host_tools = @import("build/host_tools.zig");
const hooks = @import("build/hooks.zig");
const graph_mod = @import("build/graph.zig");
const artifacts = @import("build/steps/artifacts.zig");
const checks = @import("build/steps/checks.zig");
const evidence = @import("build/steps/evidence.zig");
const tests = @import("build/steps/tests.zig");
const cross = @import("build/steps/cross.zig");
const targets = @import("build/targets.zig");
const deps = @import("build/steps/deps.zig");
const e2e = @import("build/steps/e2e.zig");
const ui = @import("build/steps/ui.zig");
const vm = @import("build/steps/vm.zig");
const example = @import("build/steps/example.zig");
const sdk = @import("build/sdk.zig");
const aot = @import("build/aot.zig");
const vnext = @import("build/vnext.zig");

pub const version = "0.1.0";

pub const Component = sdk.Component;
pub const BundleOptions = sdk.BundleOptions;
pub const Bundle = sdk.Bundle;

/// `nbpack` for the build host, for publisher steps the helpers below do not cover.
pub fn nbpack(b: *std.Build) *std.Build.Step.Compile {
    return toolchain(b).nbpack;
}

/// `nbpack component build` of `component` for `target`.
pub fn addComponent(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    component: Component,
) std.Build.LazyPath {
    return sdk.addComponent(b, toolchain(b), target.result, component);
}

/// Shipping `setup` for `target` with `product_config` (from `nbpack config`) compiled in.
pub fn addSetup(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    product_config: std.Build.LazyPath,
) *std.Build.Step.Compile {
    return sdk.addSetup(toolchain(b), target, product_config);
}

/// Fresh signed repository, branded setup and offline bundle for one release.
pub fn addBundle(b: *std.Build, options: BundleOptions) Bundle {
    return sdk.addBundle(b, toolchain(b), options);
}

fn toolchain(b: *std.Build) sdk.Toolchain {
    const dep = b.dependencyFromBuildZig(@This(), .{ .optimize = targets.shipping_optimize });
    return sdk.fromDependency(dep, version);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const tsan = b.option(bool, "tsan", "ThreadSanitizer lane for test") orelse false;
    const coverage = b.option(bool, "coverage", "kcov on zig build test") orelse false;
    const seeds: SimSeeds = .{
        .count = b.option(u32, "seeds", "Seeds for zig build test:sim") orelse 500,
        .start = b.option(u64, "seed-start", "First sim seed (replay a failure)") orelse 0,
    };
    const update = b.option([]const u8, "update", "Golden scope to rewrite (component name)");
    const product_config = b.option(std.Build.LazyPath, "product-config", "Branded setup config");
    const options: artifacts.Options = .{ .product_config = product_config, .version = version };

    const tools = checks.addTools(b, b.graph.host);
    const selected = evidence.options(
        b,
        .{
            .exe = tools.evidence,
            .seeds = seeds.count,
            .seed_start = seeds.start,
            .tsan = tsan,
            .coverage = coverage,
        },
    ) catch return;
    const config = selected.config;
    const inputs: graph_mod.Inputs = .{
        .tokens = ui.addTokens(b, tools.gen_tokens),
        .deps = deps.add(b, tools.fetch_deps),
    };
    sdk.publishInputs(b, inputs);
    const graph = graph_mod.create(
        b,
        .{ .target = target, .optimize = optimize, .inputs = inputs },
    );

    const setup = artifacts.addSetup(b, &graph, options);
    const nbpack_exe = artifacts.addNbpack(b, &graph, options);
    const static_lib = artifacts.addLibdistribution(b, &graph, .static, options);
    const dynamic_lib = artifacts.addLibdistribution(b, &graph, .dynamic, options);
    const workbench = artifacts.addWorkbench(b, &graph);
    const installed = [_]*std.Build.Step.Compile{
        setup, nbpack_exe, static_lib, dynamic_lib, workbench,
    };
    for (installed) |artifact| {
        b.installArtifact(artifact);
    }
    b.installFile("api/c/distribution.h", "include/distribution.h");

    const steps = addQualitySteps(b, &graph, tools, tsan, seeds, coverage, config);
    addTestGates(b, &graph, tools, options, config, selected, steps, .{
        .setup = setup,
        .nbpack = nbpack_exe,
        .hello = e2e.addHello(b, &graph),
        .static_lib = static_lib,
    }, workbench, update);
}

fn addTestGates(
    b: *std.Build,
    graph: *const graph_mod.Graph,
    tools: checks.Tools,
    options: artifacts.Options,
    config: evidence.Config,
    selected: evidence.Selection,
    steps: QualitySteps,
    binaries: e2e.Inputs,
    workbench: *std.Build.Step.Compile,
    update: ?[]const u8,
) void {
    const host = host_tools.add(b, tools.fetch_deps);
    const cross_steps = cross.add(b, graph.config.inputs, tools.check_binary, options);
    const cross_tests = commands.step(
        b,
        "test:cross",
        "Compile unit + conformance tests for every target",
    );
    tests.addCrossTests(b, graph.config.inputs, &app_tests, cross_tests);
    const golden_step = commands.step(
        b,
        "test:golden",
        "UI IR / DisplayList / semantic / pixel goldens",
    );
    golden_step.dependOn(ui.addGolden(b, graph, update, config));
    commands.step(
        b,
        "ui:gallery",
        "Render the UI catalog to .evidence/ui-gallery",
    ).dependOn(ui.addGallery(b, workbench));

    const e2e_step = commands.step(
        b,
        "test:e2e",
        "install/update/rollback/repair/uninstall, online + offline",
    );
    e2e_step.dependOn(e2e.addE2e(b, graph, binaries, config));
    const c_smoke = commands.step(
        b,
        "test:c-smoke",
        "C program against distribution.h + static library",
    );
    c_smoke.dependOn(e2e.addCSmoke(b, graph, binaries.static_lib, config));
    const example_step = addExampleSteps(b, graph.config.target, tools.vm_smoke, host);
    const aot_step = aot.add(b, graph.config.inputs, tools.check_binary, host);
    const core_step = vnext.add(b, graph.config.inputs, tools.fetch_deps, tools.check_binary, host);

    addRunSteps(b, binaries.setup, workbench);

    evidence.select(
        b,
        selected,
        &.{ steps.unit, steps.conformance, e2e_step, steps.sim, golden_step, steps.fuzz, c_smoke },
        steps.tsan,
    );
    const verify = commands.step(
        b,
        "verify",
        "Definition of Done gate (run with --cache-poison=disallowed)",
    );
    if (selected.narrowed) {
        verify.dependOn(&b.addFail("verify rejects -Dsuite and -Dcase narrowing").step);
        return;
    }
    verify.dependOn(core_step);
    for ([_]*std.Build.Step{
        steps.check,
        steps.unit,
        steps.conformance,
        steps.sim,
        golden_step,
        e2e_step,
        c_smoke,
        cross_steps.cross,
        cross_tests,
        cross_steps.check_binary,
        cross_steps.size_gate,
        example_step,
    }) |step| verify.dependOn(step);
    if (steps.tsan) |tsan_step| verify.dependOn(tsan_step);
    if (aot_step) |step| verify.dependOn(step);
}

/// Both build examples/hello as a separate package that depends on this one. Returns `example`.
fn addExampleSteps(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    vm_smoke: *std.Build.Step.Compile,
    host: host_tools.Tools,
) *std.Build.Step {
    const example_step = commands.step(
        b,
        "example:hello",
        "Build examples/hello (a Niobium dependent) into zig-out/example",
    );
    example_step.dependOn(example.add(b, target));
    const smoke = commands.step(
        b,
        "vm:smoke",
        "examples/hello bundles in Parallels Windows 11 + Ubuntu ARM64 (-- --start to boot VMs)",
    );
    smoke.dependOn(vm.add(b, vm_smoke, host));
    return example_step;
}

const SimSeeds = struct { count: u32, start: u64 };

const QualitySteps = struct {
    check: *std.Build.Step,
    unit: *std.Build.Step,
    conformance: *std.Build.Step,
    fuzz: *std.Build.Step,
    sim: *std.Build.Step,
    tsan: ?*std.Build.Step,
};

fn addQualitySteps(
    b: *std.Build,
    graph: *const graph_mod.Graph,
    tools: checks.Tools,
    tsan: bool,
    seeds: SimSeeds,
    coverage: bool,
    config: evidence.Config,
) QualitySteps {
    const check = addStaticChecks(b, tools);
    hooks.add(b, tools.check_commits);
    const test_step = privateStep(b, "unit");
    const naming = b.addTest(.{
        .name = "build-steps",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/commands.zig"),
            .target = b.graph.host,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(naming).step);
    const conformance = privateStep(b, "host conformance");
    addAllTests(b, graph, test_step, conformance, coverage, config);
    checks.addToolTests(b, tools, test_step, config);
    hooks.addTests(b, test_step);
    const tsan_step: ?*std.Build.Step = if (tsan or hostSupportsTsan(b)) addTsan(
        b,
        graph,
        config,
    ) else null;
    if (tsan) test_step.dependOn(tsan_step.?);

    const sim = commands.step(b, "test:sim", "Seeded VirtualPlatform fault simulation (-Dseeds=N)");
    const sim_opts = b.addOptions();
    sim_opts.addOption(u32, "seeds", seeds.count);
    sim_opts.addOption(u64, "seed_start", seeds.start);
    sim.dependOn(&tests.addSuite(b, graph, "sim", sim_opts, config).step);

    const fuzz = commands.step(
        b,
        "test:fuzz",
        "Fuzz corpus replay (continuous: -Dcontinuous-fuzz --fuzz)",
    );
    const continuous = b.option(bool, "continuous-fuzz", "Use Zig's native fuzz protocol") orelse
        false;
    const fuzz_binary = tests.compileSuite(b, graph, "fuzz", b.addOptions(), false);
    const fuzz_run = if (continuous) b.addRunArtifact(fuzz_binary) else evidence.addRun(
        b,
        config,
        .fuzz,
        fuzz_binary,
        null,
    );
    fuzz.dependOn(&fuzz_run.step);
    return .{
        .check = check,
        .unit = test_step,
        .conformance = conformance,
        .fuzz = fuzz,
        .sim = sim,
        .tsan = tsan_step,
    };
}

fn addStaticChecks(b: *std.Build, tools: checks.Tools) *std.Build.Step {
    const fmt = commands.step(b, "fmt", "zig fmt --check --ast-check");
    fmt.dependOn(checks.addFmtCheck(b));
    commands.step(b, "fmt:fix", "Rewrite sources with zig fmt").dependOn(checks.addFmtFix(b));
    const lint = commands.step(b, "lint", "TigerStyle, crash safety, and boundary rules");
    lint.dependOn(&checks.addRepoRun(b, tools.lint, &checks.source_roots).step);
    const baseline = commands.step(b, "lint:baseline", "Rewrite the complexity baseline");
    const baseline_run = checks.addRepoRun(b, tools.lint, &.{"--write-baseline"});
    baseline_run.addArgs(&checks.source_roots);
    baseline.dependOn(&baseline_run.step);
    const docs = commands.step(b, "check:docs", "Links, ADR fields, acceptance IDs, and hosts");
    docs.dependOn(&checks.addRepoRun(b, tools.check_docs, &.{}).step);
    const commits = commands.step(b, "check:commits", "Commit message lint on the branch range");
    const commit_run = checks.addRepoRun(b, tools.check_commits, &.{});
    commit_run.addPassthruArgs();
    commits.dependOn(&commit_run.step);
    const each = commands.step(
        b,
        "check:each",
        "Build check and the default build for every commit",
    );
    const each_run = checks.addRepoRun(b, tools.check_each, &.{});
    each_run.addArg(b.graph.zig_exe);
    each_run.addPassthruArgs();
    each.dependOn(&each_run.step);
    const check = commands.step(b, "check", "fmt + lint + repository checks + docs");
    check.dependOn(fmt);
    check.dependOn(lint);
    check.dependOn(docs);
    check.dependOn(&checks.addRepoRun(b, tools.check, &.{}).step);
    return check;
}

fn addAllTests(
    b: *std.Build,
    graph: *const graph_mod.Graph,
    test_step: *std.Build.Step,
    conformance_step: *std.Build.Step,
    coverage: bool,
    config: evidence.Config,
) void {
    const root: ?[]const u8 = if (coverage) "zig-out/coverage" else null;
    tests.addUnitTests(b, graph, test_step, root, config);
    const conformance = tests.compileSuite(b, graph, "conformance", b.addOptions(), coverage);
    const suite_dir = if (root) |base| b.fmt("{s}/suite-conformance", .{base}) else null;
    tests.dependOnTest(b, conformance_step, conformance, suite_dir, config, .conformance);
    tests.addAppTests(b, graph, test_step, &app_tests, root, config);
}

const app_tests = [_]tests.AppTest{
    .{
        .source = "apps/setup/main.zig",
        .imports = &artifacts.setup_imports,
        .configure = configureSetupTest,
    },
    .{
        .source = "apps/nbpack/main.zig",
        .imports = &artifacts.nbpack_imports,
        .configure = configureNbpackTest,
    },
    .{
        .source = "apps/libdistribution/root.zig",
        .imports = &artifacts.libdistribution_imports,
        .configure = configureLibdistributionTest,
    },
};

fn configureLibdistributionTest(b: *std.Build, module: *std.Build.Module) void {
    const opts = b.addOptions();
    opts.addOption([]const u8, "version", version);
    opts.addOption(bool, "branded", false);
    module.addOptions("build_options", opts);
    artifacts.configureLibdistribution(module);
}

fn configureNbpackTest(b: *std.Build, module: *std.Build.Module) void {
    const opts = b.addOptions();
    opts.addOption([]const u8, "version", version);
    opts.addOption(bool, "branded", false);
    module.addOptions("build_options", opts);
}

fn configureSetupTest(b: *std.Build, module: *std.Build.Module) void {
    const opts = b.addOptions();
    opts.addOption([]const u8, "version", version);
    opts.addOption(bool, "branded", false);
    module.addOptions("build_options", opts);
    artifacts.addProductConfig(b, module, null);
}

fn hostSupportsTsan(b: *std.Build) bool {
    return switch (b.graph.host.result.os.tag) {
        .macos, .linux => true,
        else => false,
    };
}

fn addTsan(b: *std.Build, graph: *const graph_mod.Graph, config: evidence.Config) *std.Build.Step {
    const tsan_graph = graph_mod.create(b, .{
        .target = graph.config.target,
        .optimize = .debug,
        .sanitize_thread = true,
        .inputs = graph.config.inputs,
    });
    const step = commands.step(
        b,
        "test:tsan",
        "ThreadSanitizer over engine, broker and UI-thread tests",
    );
    const opts = b.addOptions();
    opts.addOption(u32, "seeds", 16);
    var sanitizer = config;
    sanitizer.tsan = true;
    step.dependOn(&tests.addSuite(b, &tsan_graph, "concurrency", opts, sanitizer).step);
    return step;
}

fn addRunSteps(
    b: *std.Build,
    setup: *std.Build.Step.Compile,
    workbench: *std.Build.Step.Compile,
) void {
    const run_setup = b.addRunArtifact(setup);
    run_setup.addPassthruArgs();
    commands.step(b, "run", "Run setup with passthrough args").dependOn(&run_setup.step);
    const run_bench = b.addRunArtifact(workbench);
    run_bench.addPassthruArgs();
    commands.step(b, "ui:workbench", "Run ui-workbench").dependOn(&run_bench.step);
}

fn privateStep(b: *std.Build, name: []const u8) *std.Build.Step {
    const step = b.allocator.create(std.Build.Step.TopLevel) catch @panic("OOM");
    step.* = .{
        .step = .init(.{ .tag = .top_level, .name = name, .owner = b }),
        .description = name,
    };
    return &step.step;
}
