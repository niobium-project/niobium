//! Module graph rules: declared edges respect layers, UI isolation, acyclicity; roots exist.

const std = @import("std");
const repo = @import("repo");
const specs = @import("module_specs");

const Layer = specs.Layer;

fn isUi(layer: Layer) bool {
    const value = @backingInt(layer);
    return value >= @backingInt(Layer.ui_base) and value <= @backingInt(Layer.ui_backend);
}

/// Returns a reason when `from -> to` breaks the dependency direction, else null.
pub fn edgeViolation(from: specs.ModuleSpec, to: specs.ModuleSpec) ?[]const u8 {
    if (phaseViolation(from.phase, to.phase)) |reason| return reason;
    if (to.layer == .third_party) return null;
    if (from.layer == .third_party) return "third_party modules may not import project modules";
    if (isUi(from.layer)) {
        if (isUi(to.layer)) {
            if (@backingInt(to.layer) > @backingInt(from.layer)) return "UI import points upward";
            return null;
        }
        if (to.layer == .core or to.layer == .contracts) return null;
        return "UI modules may only import ui_*, contracts, core";
    }
    if (isUi(to.layer)) return "non-UI modules may not import UI modules";
    if (@backingInt(to.layer) > @backingInt(from.layer)) return "import points to a higher layer";
    return null;
}

pub fn check(report: *repo.Report, io: std.Io, files: repo.Files) !void {
    for (specs.specs, 0..) |spec, origin| {
        if (phaseClosureViolation(specs.specs.len, &specs.specs, origin)) |name| {
            try report.add("module {s} reaches forbidden phase at {s}", .{ spec.name, name });
        }
        if (!spec.generated and !repo.exists(io, spec.root)) {
            try report.add("module '{s}': root '{s}' missing", .{ spec.name, spec.root });
        }
        for (spec.imports) |name| {
            const target = specs.find(name) orelse {
                try report.add(
                    "module '{s}': imports undeclared module '{s}'",
                    .{ spec.name, name },
                );
                continue;
            };
            if (edgeViolation(spec, target)) |reason| {
                try report.add("edge {s} -> {s}: {s}", .{ spec.name, name, reason });
            }
        }
    }
    if (hasCycle()) try report.add("module graph has a cycle", .{});
    try checkOrphans(report, files);
}

/// Every libs/**/root.zig must be a declared module.
fn checkOrphans(report: *repo.Report, files: repo.Files) !void {
    for (files.paths) |path| {
        if (!std.mem.startsWith(u8, path, "libs/")) continue;
        if (!std.mem.endsWith(u8, path, "/root.zig")) continue;
        if (std.mem.startsWith(u8, path, "libs/ui/kit/") and !std.mem.eql(
            u8,
            path,
            "libs/ui/kit/root.zig",
        )) continue;
        var declared = false;
        for (specs.specs) |spec| {
            if (std.mem.eql(u8, spec.root, path)) declared = true;
        }
        if (!declared) try report.add(
            "{s}: module root not declared in build/modules.zig",
            .{path},
        );
    }
}

/// Kahn's algorithm over the declared edges; bounded by the spec count.
fn hasCycle() bool {
    const n = specs.specs.len;
    var removed: [n]bool = @splat(false);
    var round: usize = 0;
    while (round < n) : (round += 1) {
        var progressed = false;
        for (specs.specs, 0..) |spec, index| {
            if (removed[index]) continue;
            if (allImportsRemoved(spec, &removed)) {
                removed[index] = true;
                progressed = true;
            }
        }
        if (!progressed) break;
    }
    for (removed) |done| {
        if (!done) return true;
    }
    return false;
}

fn allImportsRemoved(spec: specs.ModuleSpec, removed: []const bool) bool {
    for (spec.imports) |name| {
        for (specs.specs, 0..) |candidate, index| {
            if (std.mem.eql(u8, candidate.name, name) and !removed[index]) return false;
        }
    }
    return true;
}

test "declared graph is acyclic and layered" {
    try std.testing.expect(!hasCycle());
    for (specs.specs) |spec| {
        for (spec.imports) |name| {
            const target = specs.find(name).?;
            try std.testing.expectEqual(@as(?[]const u8, null), edgeViolation(spec, target));
        }
    }
}

test "edge rules reject upward and UI leaks" {
    const engine = specs.find("engine").?;
    const core = specs.find("core").?;
    const ui_core = specs.find("ui_core").?;
    try std.testing.expect(edgeViolation(core, engine) != null);
    try std.testing.expect(edgeViolation(engine, ui_core) != null);
    try std.testing.expect(edgeViolation(ui_core, engine) != null);
}

test "install-time phase rejects compiler and policy dependencies" {
    var runtime = specs.find("runtime").?;
    const compiler = specs.find("compiler").?;
    runtime.layer = compiler.layer;
    try std.testing.expect(edgeViolation(runtime, compiler) != null);
    var preset = compiler;
    preset.phase = .policy;
    try std.testing.expect(edgeViolation(runtime, preset) != null);
}

fn phaseViolation(from: specs.Phase, to: specs.Phase) ?[]const u8 {
    if (from == .shared and to != .shared) return "shared contract depends on execution phase";
    if (from == .install_time and (to == .build_time or to == .policy)) {
        return "runtime depends on authoring or product policy";
    }
    if ((from == .build_time or from == .policy) and to == .install_time) {
        return "authoring depends on install-time implementation";
    }
    return null;
}

/// Bounded reachability also catches phase leaks hidden behind shared intermediate modules.
fn phaseClosureViolation(
    comptime count: usize,
    modules: *const [count]specs.ModuleSpec,
    origin: usize,
) ?[]const u8 {
    std.debug.assert(origin < count);
    var reachable: [count]bool = @splat(false);
    reachable[origin] = true;
    for (0..count) |_| {
        for (modules, 0..) |module, index| {
            if (!reachable[index]) continue;
            for (module.imports) |name| {
                for (modules, 0..) |target, target_index| {
                    if (!std.mem.eql(u8, target.name, name)) continue;
                    if (phaseViolation(modules[origin].phase, target.phase) != null) {
                        return target.name;
                    }
                    reachable[target_index] = true;
                }
            }
        }
    }
    return null;
}

test "runtime phase guard follows shared modules transitively" {
    const modules = [_]specs.ModuleSpec{
        .{
            .name = "run",
            .root = "",
            .layer = .orchestration,
            .phase = .install_time,
            .imports = &.{"bridge"},
        },
        .{ .name = "bridge", .root = "", .layer = .contracts, .imports = &.{"author"} },
        .{
            .name = "author",
            .root = "",
            .layer = .contracts,
            .phase = .build_time,
            .imports = &.{},
        },
    };
    try std.testing.expectEqualStrings("author", phaseClosureViolation(3, &modules, 0).?);
    var valid = modules;
    valid[2].phase = .shared;
    try std.testing.expect(phaseClosureViolation(3, &valid, 0) == null);
}
