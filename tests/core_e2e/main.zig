//! Exercise delivered setup images and inspect their real resources and durable state.
const std = @import("std");
const program = @import("program");
const kernel = @import("kernel");
const primitives = @import("host_primitives");
const image = @import("image");
const provenance = @import("suite_provenance");
const prepare = @import("prepare.zig");
const commands = @import("commands.zig");
const Dir = std.Io.Dir;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var run = try provenance.Run.startForSuite(init.arena.allocator(), init.io, args, "core-e2e");
    qualify(&run, args) catch |err| {
        try run.finish(@errorName(err));
        return err;
    };
    try run.finish(null);
    std.log.info("N2-CORE-E2E-01 PASS: {s}", .{run.evidence});
}

fn qualify(run: *provenance.Run, args: []const []const u8) !void {
    if (args.len != 12) return error.Usage;
    try run.capture();
    const target = try primitives.currentTarget();
    const directory = try run.arena.print("{s}/distribution", .{run.evidence});
    const prepared = try prepare.create(run.arena, run.io, directory, target, .{
        .runtime = args[1],
        .worker = args[2],
        .files = args[3],
        .consumer = args[4],
        .signer = if (target == .@"aarch64-macos") args[6] else null,
    });
    try prepare.models(run.arena, run.io, prepared, target);
    const upgrade = try run.arena.print("{s}/distribution-v2", .{run.evidence});
    const newer = try prepare.create(run.arena, run.io, upgrade, target, .{
        .runtime = args[1],
        .worker = args[2],
        .files = args[3],
        .consumer = args[11],
        .signer = if (target == .@"aarch64-macos") args[6] else null,
    });
    try prepare.models(run.arena, run.io, newer, target);
    const files = try commands.compile(run, args[5], prepared, "files");
    const first = try commands.compile(run, args[5], prepared, "tools-v1");
    const second = try commands.compile(run, args[5], newer, "tools-v2");
    const incompatible = try commands.compile(run, args[5], newer, "tools-invalid");
    const files_image = try checkImage(run, files);
    const tools_image = try checkImage(run, first);
    try std.testing.expectEqualSlices(
        u8,
        &files_image.template_sha256,
        &tools_image.template_sha256,
    );
    try filesLifecycle(run, files);
    try toolchainLifecycle(run, first, second, incompatible);
    try @import("frontends.zig").qualify(run, args, prepared);
    try commands.record(run, "summary", .{
        .id = "N2-CORE-E2E-01",
        .status = "PASS",
        .target = target,
        .template_sha256 = std.fmt.bytesToHex(files_image.template_sha256, .lower),
        .files_program = std.fmt.bytesToHex(files_image.program_sha256, .lower),
        .tools_program = std.fmt.bytesToHex(tools_image.program_sha256, .lower),
    });
}

pub fn checkImage(run: *provenance.Run, path: []const u8) !image.Descriptor {
    const file = try Dir.cwd().openFile(run.io, path, .{});
    defer file.close(run.io);
    const source: image.Source = .{
        .file = .{ .handle = file, .length = (try file.stat(run.io)).size },
    };
    const descriptor = try image.verify(run.arena, run.io, source, .{});
    if (@import("builtin").os.tag == .macos) {
        try image.verifyAdhoc(run.arena, run.io, source, .{});
        const report = try commands.success(
            run,
            try run.arena.print("signature-{s}", .{std.fs.path.basename(path)}),
            &.{ "/usr/bin/codesign", "--verify", "--strict", path },
        );
        try std.testing.expectEqual(@as(usize, 0), report.len);
    }
    return descriptor;
}

pub fn filesLifecycle(run: *provenance.Run, setup: []const u8) !void {
    const root = try run.arena.print("{s}/files-install", .{run.evidence});
    const installed = try commands.action(run, setup, root, "install", &.{}, "files-install");
    const state = try snapshot(run, installed);
    try std.testing.expect(state.roots[0].resources.len >= 3);
    const payload = try run.arena.print("{s}/current/sdk/README.txt", .{root});
    const bytes = try Dir.cwd().readFileAlloc(run.io, payload, run.arena, .limited(4 << 20));
    try std.testing.expectEqual(@as(usize, (2 << 20) + 17), bytes.len);
    try std.testing.expect(std.mem.allEqual(u8, bytes, 'A'));
    const empty = try Dir.cwd().openDir(
        run.io,
        try run.arena.print("{s}/current/sdk/empty", .{root}),
        .{},
    );
    empty.close(run.io);
    const disabled = try commands.action(
        run,
        setup,
        root,
        "reconfigure",
        &.{ "--set", "enabled=false" },
        "files-disabled",
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        (try snapshot(run, disabled)).roots[0].resources.len,
    );
    const enabled = try commands.action(
        run,
        setup,
        root,
        "reconfigure",
        &.{ "--set", "enabled=true", "--set", "primary=false" },
        "files-alternate",
    );
    try std.testing.expect((try snapshot(run, enabled)).roots[0].resources.len > 0);
    const alternate = try Dir.cwd().readFileAlloc(run.io, payload, run.arena, .limited(64));
    try std.testing.expectEqual(@as(usize, 17), alternate.len);
    try std.testing.expect(std.mem.allEqual(u8, alternate, 'B'));
    const removed = try commands.action(run, setup, root, "uninstall", &.{}, "files-uninstall");
    try expectRemoved(run, root, removed);
}

pub fn toolchainLifecycle(
    run: *provenance.Run,
    first: []const u8,
    second: []const u8,
    incompatible: []const u8,
) !void {
    const root = try run.arena.print("{s}/tools-install", .{run.evidence});
    const installed = try commands.action(run, first, root, "install", &.{}, "tools-install");
    try std.testing.expectEqual(@as(u32, 1), (try snapshot(run, installed)).calls[0].version);
    const path = try run.arena.print("{s}/current/toolchain/environment.txt", .{root});
    const initial = try Dir.cwd().readFileAlloc(run.io, path, run.arena, .limited(4096));
    try std.testing.expect(std.mem.indexOf(u8, initial, "label=Toolchain\n") != null);
    const platform = "platform=" ++ @tagName(@import("builtin").os.tag) ++ "\n";
    try std.testing.expect(std.mem.indexOf(u8, initial, platform) != null);
    const before = try commands.action(run, first, root, "status", &.{}, "tools-before-refusal");
    const rejected = try commands.execute(run, "tools-missing-migration", &.{
        incompatible, "update", "--root", try run.arena.print("application={s}", .{root}),
    });
    try std.testing.expect(!rejected.term.success());
    const after = try commands.action(run, first, root, "status", &.{}, "tools-after-refusal");
    try std.testing.expectEqualStrings(before, after);
    const updated = try commands.action(run, second, root, "update", &.{}, "tools-update");
    const state = try snapshot(run, updated);
    try std.testing.expectEqual(@as(u32, 2), state.calls[0].version);
    try std.testing.expectEqualStrings("v2:enabled", state.calls[0].value.?.text);
    try std.testing.expectEqual(@as(usize, 1), state.migrations.len);
    const current = try Dir.cwd().readFileAlloc(run.io, path, run.arena, .limited(4096));
    try std.testing.expect(std.mem.indexOf(u8, current, "previous=v2:enabled\n") != null);
    const reconfigured = try commands.action(
        run,
        second,
        root,
        "reconfigure",
        &.{ "--set", "label=Selected SDK", "--set", "primary=false" },
        "tools-reconfigure",
    );
    try std.testing.expectEqual(@as(usize, 1), (try snapshot(run, reconfigured)).migrations.len);
    const changed = try Dir.cwd().readFileAlloc(run.io, path, run.arena, .limited(4096));
    try std.testing.expect(std.mem.indexOf(u8, changed, "label=Selected SDK\n") != null);
    try std.testing.expect(!std.mem.eql(u8, current, changed));
    const removed = try commands.action(run, second, root, "uninstall", &.{}, "tools-uninstall");
    try expectRemoved(run, root, removed);
    try freshSecondRelease(run, second);
}

fn freshSecondRelease(run: *provenance.Run, setup: []const u8) !void {
    const root = try run.arena.print("{s}/tools-fresh-v2", .{run.evidence});
    const installed = try commands.action(run, setup, root, "install", &.{}, "tools-fresh-v2");
    const state = try snapshot(run, installed);
    try std.testing.expectEqual(@as(u32, 2), state.calls[0].version);
    try std.testing.expectEqualStrings("v2:enabled", state.calls[0].value.?.text);
    try std.testing.expectEqual(@as(usize, 0), state.migrations.len);
    const removed = try commands.action(
        run,
        setup,
        root,
        "uninstall",
        &.{},
        "tools-fresh-v2-remove",
    );
    try expectRemoved(run, root, removed);
}

fn snapshot(run: *provenance.Run, bytes: []const u8) !kernel.Snapshot {
    const result = try std.json.parseFromSliceLeaky(kernel.Result, run.arena, bytes, .{});
    return result.state orelse error.MissingState;
}

fn expectRemoved(run: *provenance.Run, root: []const u8, bytes: []const u8) !void {
    const result = try std.json.parseFromSliceLeaky(kernel.Result, run.arena, bytes, .{});
    try std.testing.expect(result.state == null);
    const path = try run.arena.print("{s}/current", .{root});
    try std.testing.expectError(error.FileNotFound, Dir.cwd().access(run.io, path, .{}));
}
