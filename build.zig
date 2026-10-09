//! Current product tools, independent components, and their verification gates.
const std = @import("std");
const commands = @import("build/commands.zig");
const host_tools = @import("build/host_tools.zig");
const hooks = @import("build/hooks.zig");
const graph_mod = @import("build/graph.zig");
const checks = @import("build/steps/checks.zig");
const evidence = @import("build/steps/evidence.zig");
const tests = @import("build/steps/tests.zig");
const deps = @import("build/steps/deps.zig");
const ui = @import("build/steps/ui.zig");
const product = @import("build/product.zig");

pub const version = "0.1.0";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const tsan = b.option(bool, "tsan", "ThreadSanitizer for independent concurrency tests") orelse
        false;
    const coverage = b.option(bool, "coverage", "kcov on selected tests") orelse false;
    const update = b.option([]const u8, "update", "Golden scope to rewrite (component name)");
    const tools = checks.addTools(b, b.graph.host);
    const selected = evidence.options(b, .{
        .exe = tools.evidence,
        .tsan = tsan,
        .coverage = coverage,
    }) catch return;
    const inputs: graph_mod.Inputs = .{
        .tokens = ui.addTokens(b, tools.gen_tokens),
        .deps = deps.add(b, tools.fetch_deps),
    };
    const graph = graph_mod.create(b, .{
        .target = target,
        .optimize = optimize,
        .inputs = inputs,
    });
    b.modules.put(b.allocator, "compiler", graph.get("compiler")) catch @panic("OOM");
    const gallery = addGallery(b, &graph);
    b.installArtifact(gallery);
    const host = host_tools.add(b, tools.fetch_deps);
    const core = product.add(b, inputs, tools.fetch_deps, tools.check_binary, host);
    addGates(b, &graph, tools, selected, core, inputs, tsan, coverage, update);
}

fn addGates(
    b: *std.Build,
    graph: *const graph_mod.Graph,
    tools: checks.Tools,
    selected: evidence.Selection,
    core: *std.Build.Step,
    inputs: graph_mod.Inputs,
    tsan: bool,
    coverage: bool,
    update: ?[]const u8,
) void {
    const static_checks = addStaticChecks(b, tools);
    const unit = privateStep(b, "unit");
    tests.addUnitTests(
        b,
        graph,
        unit,
        if (coverage) "zig-out/coverage" else null,
        selected.config,
    );
    checks.addToolTests(b, tools, unit, selected.config);
    hooks.addTests(b, unit);
    const naming = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("build/commands.zig"),
        .target = b.graph.host,
    }) });
    unit.dependOn(&b.addRunArtifact(naming).step);
    const conformance = privateStep(b, "host conformance");
    conformance.dependOn(&tests.addSuite(
        b,
        graph,
        "conformance",
        b.addOptions(),
        selected.config,
    ).step);
    const golden = commands.step(b, "test:golden", "UI semantic, display and pixel goldens");
    golden.dependOn(ui.addGolden(b, graph, update, selected.config));
    const fuzz = addFuzz(b, graph, selected.config);
    const cross = commands.step(b, "test:cross", "Compile independent contracts for every target");
    tests.addCrossTests(b, inputs, &.{}, cross);
    const host_os = b.graph.host.result.os.tag;
    const sanitizer_supported = host_os == .macos or host_os == .linux;
    const tsan_step = if (tsan or sanitizer_supported)
        addTsan(b, inputs, selected.config)
    else
        null;
    // The evidence protocol retains suite identities; removed suites cannot be selected.
    const retired = &b.addFail("Retired manifest suite; use test:kernel or test:author").step;
    evidence.select(b, selected, &.{
        unit, conformance, core, retired, golden, fuzz, retired,
    }, tsan_step);
    const verify = commands.step(
        b,
        "verify",
        "All current product and independent component gates",
    );
    if (selected.narrowed) {
        verify.dependOn(&b.addFail("verify rejects -Dsuite and -Dcase narrowing").step);
        return;
    }
    for ([_]*std.Build.Step{ static_checks, unit, conformance, golden, fuzz, cross, core }) |step| {
        verify.dependOn(step);
    }
    if (tsan_step) |step| verify.dependOn(step);
}

fn addFuzz(
    b: *std.Build,
    graph: *const graph_mod.Graph,
    config: evidence.Config,
) *std.Build.Step {
    const step = commands.step(b, "test:fuzz", "Current product and independent extraction corpus");
    const continuous = b.option(bool, "continuous-fuzz", "Use Zig's native fuzz protocol") orelse
        false;
    const binary = tests.compileSuite(b, graph, "fuzz", b.addOptions(), false);
    const run = if (continuous)
        b.addRunArtifact(binary)
    else
        evidence.addRun(b, config, .fuzz, binary, null);
    if (continuous) run.addPassthruArgs();
    step.dependOn(&run.step);
    return step;
}

fn addGallery(b: *std.Build, graph: *const graph_mod.Graph) *std.Build.Step.Compile {
    const module = graph.root("apps/ui-gallery/main.zig", &.{
        "ui_core",   "ui_kit",     "ui_screens", "ui_render",
        "ui_tokens", "ui_backend", "contracts",  "core",
    });
    const gallery = b.addExecutable(.{ .name = "nb-ui-gallery", .root_module = module });
    commands.step(b, "ui:gallery", "Render the component catalog to .evidence/ui-gallery")
        .dependOn(ui.addGallery(b, gallery));
    const run = b.addRunArtifact(gallery);
    run.addPassthruArgs();
    commands.step(b, "ui:run", "Open the UI component gallery").dependOn(&run.step);
    return gallery;
}

fn addStaticChecks(b: *std.Build, tools: checks.Tools) *std.Build.Step {
    const fmt = commands.step(b, "fmt", "zig fmt --check --ast-check");
    fmt.dependOn(checks.addFmtCheck(b));
    commands.step(b, "fmt:fix", "Rewrite sources with zig fmt").dependOn(checks.addFmtFix(b));
    const lint = commands.step(b, "lint", "TigerStyle, crash safety, and boundary rules");
    lint.dependOn(&checks.addRepoRun(b, tools.lint, &checks.source_roots).step);
    const baseline = checks.addRepoRun(b, tools.lint, &.{"--write-baseline"});
    baseline.addArgs(&checks.source_roots);
    commands.step(b, "lint:baseline", "Rewrite the complexity baseline").dependOn(&baseline.step);
    const docs = commands.step(b, "check:docs", "Links, ADR fields, acceptance IDs, and hosts");
    docs.dependOn(&checks.addRepoRun(b, tools.check_docs, &.{}).step);
    const commit_run = checks.addRepoRun(b, tools.check_commits, &.{});
    commit_run.addPassthruArgs();
    commands.step(b, "check:commits", "Commit message lint").dependOn(&commit_run.step);
    hooks.add(b, tools.check_commits);
    const each = commands.step(
        b,
        "check:each",
        "Build check and the default build for every commit",
    );
    const each_run = checks.addRepoRun(b, tools.check_each, &.{});
    each_run.addArg(b.graph.zig_exe);
    each_run.addPassthruArgs();
    each.dependOn(&each_run.step);
    const check = commands.step(b, "check", "Format, lint, boundaries, and documentation");
    const repo_check = checks.addRepoRun(b, tools.check, &.{});
    for ([_]*std.Build.Step{ fmt, lint, docs, &repo_check.step }) |step| {
        check.dependOn(step);
    }
    return check;
}

fn addTsan(
    b: *std.Build,
    inputs: graph_mod.Inputs,
    config: evidence.Config,
) *std.Build.Step {
    const graph = graph_mod.create(b, .{
        .target = b.graph.host,
        .optimize = .debug,
        .sanitize_thread = true,
        .inputs = inputs,
    });
    var sanitizer = config;
    sanitizer.tsan = true;
    const step = commands.step(
        b,
        "test:tsan",
        "ThreadSanitizer over independent concurrency tests",
    );
    step.dependOn(&tests.addSuite(b, &graph, "concurrency", b.addOptions(), sanitizer).step);
    return step;
}

fn privateStep(b: *std.Build, name: []const u8) *std.Build.Step {
    const step = b.allocator.create(std.Build.Step.TopLevel) catch @panic("OOM");
    step.* = .{
        .step = .init(.{ .tag = .top_level, .name = name, .owner = b }),
        .description = name,
    };
    return &step.step;
}
