//! Post-build binary lint and size gate.
//!   nb-check-binary lint [--profile legacy|component] --target <name> --kind exe|dylib <file>
//!   nb-check-binary size --baseline <zon> --limit <bytes> [--write] (<name> <file>)...

const std = @import("std");
const repo = @import("repo");
const bytes = @import("bytes.zig");
const allowlist = @import("allowlist.zig");
const size = @import("size.zig");

const max_binary_bytes = 256 << 20;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) return error.UsageMissingCommand;
    if (std.mem.eql(u8, args[1], "lint")) return lintCommand(arena, io, args[2..]);
    if (std.mem.eql(u8, args[1], "size")) return size.command(arena, io, args[2..]);
    if (std.mem.eql(u8, args[1], "dump") and args.len == 3) return dump(arena, io, args[2]);
    return error.UsageUnknownCommand;
}

fn lintCommand(arena: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    const options = try parseOptions(args);
    const path = options.path;
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_binary_bytes));
    const facts = try parse(arena, data);
    var report: repo.Report = .{ .arena = arena, .tool = "check-binary" };
    try checkProfile(
        &report,
        options.profile,
        options.target,
        options.kind,
        std.fs.path.basename(path),
        facts,
    );
    try report.finish(io);
}

const Options = struct {
    profile: allowlist.Profile = .legacy,
    target: []const u8,
    kind: allowlist.Kind,
    path: []const u8,
};

fn parseOptions(args: []const []const u8) error{UsageLint}!Options {
    if (args.len != 5 and args.len != 7) return error.UsageLint;
    var profile: ?allowlist.Profile = null;
    var target: ?[]const u8 = null;
    var kind: ?allowlist.Kind = null;
    var index: usize = 0;
    while (index < args.len - 1) : (index += 2) {
        const name = args[index];
        const value = args[index + 1];
        if (std.mem.eql(u8, name, "--profile")) {
            if (profile != null) return error.UsageLint;
            profile = std.meta.stringToEnum(allowlist.Profile, value) orelse return error.UsageLint;
        } else if (std.mem.eql(u8, name, "--target")) {
            if (target != null or value.len == 0) return error.UsageLint;
            target = value;
        } else if (std.mem.eql(u8, name, "--kind")) {
            if (kind != null) return error.UsageLint;
            kind = std.meta.stringToEnum(allowlist.Kind, value) orelse return error.UsageLint;
        } else return error.UsageLint;
    }
    return .{
        .profile = profile orelse .legacy,
        .target = target orelse return error.UsageLint,
        .kind = kind orelse return error.UsageLint,
        .path = args[args.len - 1],
    };
}

fn dump(arena: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_binary_bytes));
    const facts = try parse(arena, data);
    std.debug.print("{s}: {s}\n", .{ path, @tagName(facts.format) });
    for (facts.dependencies) |dependency| std.debug.print("  needs {s}\n", .{dependency});
    if (facts.interpreter) |path_| std.debug.print("  interpreter {s}\n", .{path_});
    for (facts.writable_executable) |section| std.debug.print("  rwx {s}\n", .{section});
    std.debug.print("  exec_stack={} aslr={?} nx={?} high_entropy={?}\n", .{
        facts.executable_stack, facts.aslr, facts.dep_nx, facts.high_entropy_va,
    });
}

pub fn parse(arena: std.mem.Allocator, data: []const u8) !bytes.Facts {
    if (std.mem.startsWith(u8, data, "MZ")) return @import("pe.zig").parse(arena, data);
    if (std.mem.startsWith(u8, data, "\x7fELF")) return @import("elf.zig").parse(arena, data);
    if (std.mem.startsWith(
        u8,
        data,
        "\xcf\xfa\xed\xfe",
    )) return @import("macho.zig").parse(arena, data);
    return error.BinaryUnknownFormat;
}

pub fn check(
    report: *repo.Report,
    target: []const u8,
    kind: allowlist.Kind,
    name: []const u8,
    facts: bytes.Facts,
) !void {
    return checkProfile(report, .legacy, target, kind, name, facts);
}

pub fn checkProfile(
    report: *repo.Report,
    profile: allowlist.Profile,
    target: []const u8,
    kind: allowlist.Kind,
    name: []const u8,
    facts: bytes.Facts,
) !void {
    const rule = findRule(profile, target, kind) orelse {
        return report.add(
            "{s}: no allowlist for profile {s}, target {s} ({s})",
            .{ name, @tagName(profile), target, @tagName(kind) },
        );
    };
    if (profile == .component) {
        if (rule.format != facts.format) try report.add("{s}: unexpected native format", .{name});
        const same = if (rule.interpreter) |expected|
            if (facts.interpreter) |actual| std.mem.eql(u8, expected, actual) else false
        else
            facts.interpreter == null;
        if (!same) try report.add("{s}: unexpected ELF interpreter", .{name});
    }
    for (facts.dependencies) |dependency| {
        if (!allowed(rule, facts.format, dependency)) {
            try report.add("{s}: undeclared dynamic dependency {s}", .{ name, dependency });
        }
    }
    for (facts.writable_executable) |section| {
        try report.add("{s}: writable+executable section {s}", .{ name, section });
    }
    if (facts.executable_stack) try report.add("{s}: executable stack (PT_GNU_STACK)", .{name});
    if (facts.aslr == false) try report.add("{s}: PE without DYNAMICBASE (ASLR)", .{name});
    if (facts.dep_nx == false) try report.add("{s}: PE without NXCOMPAT (DEP)", .{name});
    if (facts.high_entropy_va == false) try report.add("{s}: PE without HIGHENTROPYVA", .{name});
}

fn findRule(profile: allowlist.Profile, target: []const u8, kind: allowlist.Kind) ?allowlist.Rule {
    const rules: []const allowlist.Rule = switch (profile) {
        .legacy => &allowlist.rules,
        .component => &allowlist.component_rules,
    };
    for (rules) |rule| {
        if (rule.kind == kind and std.mem.eql(u8, rule.target, target)) return rule;
    }
    return null;
}

fn allowed(rule: allowlist.Rule, format: bytes.Format, dependency: []const u8) bool {
    for (rule.dependencies) |entry| {
        const same = if (format == .pe)
            std.ascii.eqlIgnoreCase(entry, dependency)
        else
            std.mem.eql(u8, entry, dependency);
        if (same) return true;
    }
    return false;
}

test "policy flags undeclared deps, RWX and missing PE hardening" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    var report: repo.Report = .{ .arena = arena_state.allocator(), .tool = "test" };
    try check(&report, "x86_64-windows", .exe, "setup.exe", .{
        .format = .pe,
        .dependencies = &.{ "KERNEL32.dll", "evil.dll" },
        .writable_executable = &.{".text"},
        .aslr = true,
        .dep_nx = false,
        .high_entropy_va = true,
    });
    try std.testing.expectEqual(@as(usize, 3), report.findings.items.len);
}

test "clean static ELF passes" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    var report: repo.Report = .{ .arena = arena_state.allocator(), .tool = "test" };
    try check(&report, "x86_64-linux", .exe, "setup", .{
        .format = .elf,
        .dependencies = &.{},
        .writable_executable = &.{},
    });
    try std.testing.expectEqual(@as(usize, 0), report.findings.items.len);
}

test "N2-BINARY-01 Component API sets require an explicit qualified profile" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const facts: bytes.Facts = .{
        .format = .pe,
        .dependencies = &.{"api-ms-win-crt-heap-l1-1-0.dll"},
        .writable_executable = &.{},
    };
    var legacy: repo.Report = .{ .arena = arena.allocator(), .tool = "test" };
    try check(&legacy, "x86_64-windows", .exe, "legacy.exe", facts);
    try std.testing.expectEqual(@as(usize, 1), legacy.findings.items.len);
    var component: repo.Report = .{ .arena = arena.allocator(), .tool = "test" };
    try checkProfile(&component, .component, "x86_64-windows-gnu", .exe, "runtime.exe", facts);
    try std.testing.expectEqual(@as(usize, 0), component.findings.items.len);
}

test "N2-BINARY-01 Component rules reject undeclared runtimes and retain hardening" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var report: repo.Report = .{ .arena = arena.allocator(), .tool = "test" };
    try checkProfile(&report, .component, "x86_64-windows-gnu", .exe, "runtime.exe", .{
        .format = .pe,
        .dependencies = &.{
            "vcruntime140.dll", "private.dll", "api-ms-win-crt-unlisted-l1-1-0.dll",
        },
        .writable_executable = &.{".text"},
        .aslr = false,
        .dep_nx = false,
        .high_entropy_va = false,
    });
    try std.testing.expectEqual(@as(usize, 7), report.findings.items.len);
}

test "N2-BINARY-01 static Component ABI never permits a loader or libc dependency" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var report: repo.Report = .{ .arena = arena.allocator(), .tool = "test" };
    try checkProfile(&report, .component, "x86_64-linux-musl", .exe, "runtime", .{
        .format = .elf,
        .dependencies = &.{"libc.so.6"},
        .writable_executable = &.{},
        .interpreter = "/lib64/ld-linux-x86-64.so.2",
    });
    try std.testing.expectEqual(@as(usize, 2), report.findings.items.len);
    try std.testing.expectEqual(.legacy, (try parseOptions(&.{
        "--target", "x86_64-linux", "--kind", "exe", "file",
    })).profile);
    try std.testing.expectError(error.UsageLint, parseOptions(&.{
        "--profile", "unknown", "--target", "x86_64-linux-musl", "--kind", "exe", "file",
    }));
}

test "N2-BINARY-01 GNU profile requires its measured loader and native format" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var report: repo.Report = .{ .arena = arena.allocator(), .tool = "test" };
    const facts: bytes.Facts = .{
        .format = .elf,
        .writable_executable = &.{},
        .dependencies = &.{ "libc.so.6", "ld-linux-x86-64.so.2" },
        .interpreter = "/lib64/ld-linux-x86-64.so.2",
    };
    try checkProfile(&report, .component, "x86_64-linux-gnu", .exe, "runtime", facts);
    try std.testing.expectEqual(@as(usize, 0), report.findings.items.len);
    var altered = facts;
    altered.interpreter = "/private/loader";
    try checkProfile(&report, .component, "x86_64-linux-gnu", .exe, "runtime", altered);
    try std.testing.expectEqual(@as(usize, 1), report.findings.items.len);
    altered = facts;
    altered.format = .pe;
    try checkProfile(&report, .component, "x86_64-linux-gnu", .exe, "runtime", altered);
    try std.testing.expectEqual(@as(usize, 2), report.findings.items.len);
    try checkProfile(&report, .component, "x86_64-windows-msvc", .exe, "runtime", facts);
    try std.testing.expectEqual(@as(usize, 3), report.findings.items.len);
}

test {
    _ = bytes;
    _ = @import("pe.zig");
    _ = @import("elf.zig");
    _ = @import("macho.zig");
    _ = size;
}
