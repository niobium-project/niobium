//! Native kernel contracts. Cross-process durability tests live in tests/kernel.
const std = @import("std");
const program = @import("program");
const content = @import("content");
const access = @import("access");
const platform = @import("platform");
const kernel = @import("kernel");
const Fixture = @import("fixture.zig").Fixture;
const io = std.testing.io;

test {
    _ = @import("budget_test.zig");
    _ = @import("input_test.zig");
    _ = @import("migration_test.zig");
    _ = @import("link_test.zig");
}

test "N2-KERNEL-01: two named roots install reconfigure migrate and uninstall" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 2);
    var host: platform.Host = .init(io, .{ .env = .{} });
    var options = try fixture.options(&host, .install);
    const installed = try kernel.run(options);
    try std.testing.expectEqual(@as(usize, 2), installed.state.?.roots.len);
    try fixture.expectFiles("first");
    options.action = .reconfigure;
    options.inputs = &.{.{ .id = "label", .value = .{ .text = "Unicode 世界" } }};
    const configured = try kernel.run(options);
    try std.testing.expectEqualStrings("Unicode 世界", configured.state.?.inputs[0].value.text);
    try fixture.setContent("second");
    fixture.version = 2;
    options = try fixture.options(&host, .update);
    const updated = try kernel.run(options);
    try std.testing.expectEqual(@as(u32, 2), updated.state.?.calls[0].version);
    try std.testing.expectEqual(@as(usize, 1), updated.state.?.migrations.len);
    try fixture.expectFiles("second");
    options.action = .uninstall;
    const removed = try kernel.run(options);
    try std.testing.expect(removed.state == null);
    for (fixture.roots) |root| {
        const path = try std.fs.path.join(arena.allocator(), &.{ root.path, "current" });
        try std.testing.expect(
            (try platform.local.readPointer(
                io,
                arena.allocator(),
                path,
            )) == null,
        );
    }
}

test "N2-KERNEL-02: optional empty desired tree clears state and preserves user-added files" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{} });
    const first = try kernel.run(try fixture.options(&host, .install));
    const old = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path,
            ".niobium-v2",
            "generations",
            first.state.?.roots[0].generation,
            "data",
            "extra",
        },
    );
    try host.platform().writeFile(old, "user", false);
    fixture.empty = true;
    const next = try kernel.run(try fixture.options(&host, .reconfigure));
    try std.testing.expectEqual(@as(usize, 0), next.state.?.roots[0].resources.len);
    try std.testing.expectEqual(@as(usize, 1), next.state.?.calls.len);
    try std.testing.expect(next.state.?.calls[0].value == null);
    const retained = try std.Io.Dir.cwd().readFileAlloc(io, old, arena.allocator(), .limited(16));
    try std.testing.expectEqualStrings("user", retained);
}

test "N2-KERNEL-03: grant escalation digest mismatch and missing migration fail before activation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{} });
    fixture.escalate = true;
    try std.testing.expectError(
        error.ProgramAuthority,
        kernel.run(
            try fixture.options(
                &host,
                .install,
            ),
        ),
    );
    fixture.escalate = false;
    fixture.corrupt = true;
    try std.testing.expectError(
        error.ProgramDigest,
        kernel.run(
            try fixture.options(
                &host,
                .install,
            ),
        ),
    );
    fixture.corrupt = false;
    const installed = try kernel.run(try fixture.options(&host, .install));
    try std.testing.expect(installed.state != null);
    fixture.version = 2;
    fixture.migration = false;
    try std.testing.expectError(
        error.KernelUpgrade,
        kernel.run(
            try fixture.options(
                &host,
                .update,
            ),
        ),
    );
    try fixture.expectFiles("first");
    fixture.migration = true;
    fixture.receipt = false;
    try std.testing.expectError(
        error.KernelEvaluation,
        kernel.run(
            try fixture.options(
                &host,
                .update,
            ),
        ),
    );
}

test "N2-KERNEL-04: unknown plan versions and foreign roots are rejected without mutation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{} });
    const installed = try kernel.run(try fixture.options(&host, .install));
    try std.testing.expect(installed.state != null);
    const pending = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path, ".niobium-v2", "pending.json",
        },
    );
    try host.platform().writeFile(pending, "{\"schema\":99}", false);
    const lock = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path, ".niobium-lock",
        },
    );
    try std.Io.Dir.cwd().deleteFile(io, lock);
    var options = try fixture.options(&host, .recover);
    options.model = null;
    options.evaluator = .{};
    options.content = .{};
    try std.testing.expectError(error.UnsupportedSchema, kernel.run(options));
    try fixture.expectFiles("first");
    const retained = try std.Io.Dir.cwd().readFileAlloc(
        io,
        pending,
        arena.allocator(),
        .limited(
            64,
        ),
    );
    try std.testing.expectEqualStrings("{\"schema\":99}", retained);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, lock, .{}));
}

test "N2-KERNEL-06: read-only payload access is restored and source modes grant nothing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    fixture.file_policy.owner.write = false;
    fixture.directory_policy.owner.write = false;
    var host: platform.Host = .init(io, .{ .env = .{} });
    const installed = try kernel.run(try fixture.options(&host, .install));
    try fixture.expectFiles("first");
    const actual_dir = try std.Io.Dir.cwd().openDir(
        io,
        try std.fs.path.join(arena.allocator(), &.{ fixture.roots[0].path, "current", "bin" }),
        .{},
    );
    defer actual_dir.close(io);
    const file = try access.openForAccess(arena.allocator(), io, actual_dir, "tool");
    defer file.file.close(io);
    try std.testing.expect(!file.observation.policy.owner.write);
    try std.testing.expect(!file.observation.policy.owner.execute);
    try std.testing.expect(!file.observation.policy.everyone.read);
    const removed = try kernel.run(try fixture.options(&host, .uninstall));
    try std.testing.expect(removed.state == null);
    const old = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path,
            ".niobium-v2",
            "generations",
            installed.state.?.roots[0].generation,
            "data",
            "bin",
            "tool",
        },
    );
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, old, .{}));
}

test "N2-KERNEL-07: legacy or nonempty unowned roots cannot be adopted" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{} });
    try std.Io.Dir.cwd().createDir(io, fixture.roots[0].path, .default_dir);
    const old = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path, "installation.json",
        },
    );
    try host.platform().writeFile(old, "{\"schema\":1}", false);
    try std.testing.expectError(
        error.KernelOwnership,
        kernel.run(
            try fixture.options(
                &host,
                .install,
            ),
        ),
    );
    const retained = try std.Io.Dir.cwd().readFileAlloc(io, old, arena.allocator(), .limited(64));
    try std.testing.expectEqualStrings("{\"schema\":1}", retained);
    const lock = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path, ".niobium-lock",
        },
    );
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, lock, .{}));
}

test "N2-KERNEL-08: confined symlink is exact or explicitly unsupported before publication" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var output: std.Io.Writer.Allocating = .init(arena.allocator());
    fixture.reference = try content.writeTar(
        arena.allocator(),
        io,
        .{
            .entries = &.{
                .{ .path = "bin/tool", .body = .bytes("first") },
                .{ .path = "tool", .kind = .symlink, .link_target = "./bin/tool" },
            },
        },
        &output.writer,
        .{},
    );
    fixture.tar = output.written();
    var host: platform.Host = .init(io, .{ .env = .{} });
    const installed = kernel.run(try fixture.options(&host, .install)) catch |err| {
        if (@import("builtin").os.tag != .windows or err != error.KernelUnsupported) return err;
        std.debug.print("Native file-link context: unsupported before publication\n", .{});
        var recovery = try fixture.options(&host, .recover);
        recovery.model = null;
        recovery.evaluator = .{};
        recovery.content = .{};
        const reverted = try kernel.run(recovery);
        try std.testing.expect(reverted.state == null);
        const absent = try std.fs.path.join(
            arena.allocator(),
            &.{
                fixture.roots[0].path, "current",
            },
        );
        try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, absent, .{}));
        return;
    };
    try std.testing.expect(installed.state != null);
    const link = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path, "current", "tool",
        },
    );
    var target: [64]u8 = undefined; // SAFETY: readLink initializes its returned prefix.
    const length = try std.Io.Dir.cwd().readLink(io, link, &target);
    const projected = try kernel.wire.nativeLinkTarget(arena.allocator(), "./bin/tool");
    try std.testing.expectEqualStrings(projected, target[0..length]);
    const logical = installed.state.?.roots[0].resources[2].link_target;
    try std.testing.expectEqualStrings("./bin/tool", logical);
    const removed = try kernel.run(try fixture.options(&host, .uninstall));
    try std.testing.expect(removed.state == null);
}

test "N2-KERNEL-09: repair restores desired bytes while retaining modified prior content" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{} });
    const installed = try kernel.run(try fixture.options(&host, .install));
    const old = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path,
            ".niobium-v2",
            "generations",
            installed.state.?.roots[0].generation,
            "data",
            "bin",
            "tool",
        },
    );
    try host.platform().writeFile(old, "user-edited", false);
    const repaired = try kernel.run(try fixture.options(&host, .repair));
    try std.testing.expect(repaired.state != null);
    try fixture.expectFiles("first");
    const retained = try std.Io.Dir.cwd().readFileAlloc(io, old, arena.allocator(), .limited(64));
    try std.testing.expectEqualStrings("user-edited", retained);
}

test "N2-KERNEL-10: preexisting pointer work files survive rejection" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{} });
    const installed = try kernel.run(try fixture.options(&host, .install));
    try std.testing.expect(installed.state != null);
    const next = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path, "current.next",
        },
    );
    try host.platform().writeFile(next, "unowned pointer work file", false);
    try std.testing.expectError(
        error.KernelConflict,
        kernel.run(
            try fixture.options(
                &host,
                .reconfigure,
            ),
        ),
    );
    const retained = try std.Io.Dir.cwd().readFileAlloc(io, next, arena.allocator(), .limited(64));
    try std.testing.expectEqualStrings("unowned pointer work file", retained);
    try fixture.expectFiles("first");
}

test "N2-KERNEL-11: malformed durable model migration history is rejected" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{} });
    const installed = try kernel.run(try fixture.options(&host, .install));
    var state = installed.state.?;
    state.model_migrations = &.{.{ .id = "invalid", .from = 0, .to = 1 }};
    const path = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path, ".niobium-v2", "installation.json",
        },
    );
    const bytes = try std.json.Stringify.valueAlloc(arena.allocator(), state, .{});
    try host.platform().writeFile(path, bytes, false);
    try std.testing.expectError(error.KernelState, kernel.run(try fixture.options(&host, .status)));
    const retained = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        arena.allocator(),
        .limited(
            1 << 20,
        ),
    );
    try std.testing.expectEqualStrings(bytes, retained);
    try fixture.expectFiles("first");
}

test "N2-KERNEL-12: a stateless plan cannot discard capability ownership" {
    for ([_]bool{ false, true }) |change_library| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
        fixture.empty = true;
        var host: platform.Host = .init(io, .{ .env = .{} });
        const installed = try kernel.run(try fixture.options(&host, .install));
        try std.testing.expect(installed.state != null);
        fixture.version = 2;
        var options = try fixture.options(&host, .update);
        var model = options.model.?;
        const calls = try arena.allocator().dupe(program.model.Call, model.calls);
        calls[0].state_version = 1;
        calls[0].migrations = &.{};
        if (change_library) {
            const libraries = try arena.allocator().dupe(program.model.Library, model.libraries);
            libraries[0].id = "other-library";
            calls[0].library = "other-library";
            model.libraries = libraries;
        } else calls[0].function = "other-function";
        model.calls = calls;
        options.model = model;
        try std.testing.expectError(error.KernelUpgrade, kernel.run(options));
    }
}

test "N2-KERNEL-13: null private state retains version and refuses value-consuming migration" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    fixture.empty = true;
    var host: platform.Host = .init(io, .{ .env = .{} });
    const first = try kernel.run(try fixture.options(&host, .install));
    try std.testing.expectEqual(@as(usize, 1), first.state.?.calls.len);
    try std.testing.expect(first.state.?.calls[0].value == null);
    fixture.version = 2;
    try std.testing.expectError(
        error.KernelUpgrade,
        kernel.run(
            try fixture.options(
                &host,
                .update,
            ),
        ),
    );
    var options = try fixture.options(&host, .update);
    var model = options.model.?;
    const calls = try arena.allocator().dupe(program.model.Call, model.calls);
    calls[0].state_version = 1;
    calls[0].migrations = &.{};
    model.calls = calls;
    options.model = model;
    const next = try kernel.run(options);
    try std.testing.expectEqual(@as(usize, 1), next.state.?.calls.len);
    try std.testing.expectEqual(@as(u32, 1), next.state.?.calls[0].version);
    try std.testing.expectEqual(@as(u64, 2), next.state.?.release_sequence);
    try std.testing.expect(next.state.?.calls[0].value == null);
}

test "N2-KERNEL-16: target names follow the native filesystem contract" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var output: std.Io.Writer.Allocating = .init(arena.allocator());
    const entries = [_]content.Entry{
        .{ .path = "CON", .body = .bytes("con") },
        .{ .path = "file:name", .body = .bytes("colon") },
        .{ .path = "back\\slash", .body = .bytes("backslash") },
        .{ .path = "trailing.", .body = .bytes("dot") },
    };
    fixture.reference = try content.writeTar(
        arena.allocator(),
        io,
        .{
            .entries = &entries,
        },
        &output.writer,
        .{},
    );
    fixture.tar = output.written();
    var host: platform.Host = .init(io, .{ .env = .{} });
    if (@import("builtin").os.tag == .windows) {
        try std.testing.expectError(
            error.ProgramPath,
            kernel.run(
                try fixture.options(
                    &host,
                    .install,
                ),
            ),
        );
        return;
    }
    const installed = try kernel.run(try fixture.options(&host, .install));
    try std.testing.expectEqual(@as(usize, 4), installed.state.?.roots[0].resources.len);
    for (entries) |entry| {
        const path = try std.fs.path.join(
            arena.allocator(),
            &.{
                fixture.roots[0].path, "current", entry.path,
            },
        );
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, arena.allocator(), .limited(64));
        try std.testing.expectEqualStrings(entry.body.source.bytes, bytes);
    }
}

test "N2-KERNEL-17: native alias collisions reject before publication without global folding" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const first = try tmp.dir.createFile(io, "CaseProbe", .{ .exclusive = true });
    first.close(io);
    var sensitive = true;
    if (tmp.dir.createFile(io, "caseprobe", .{ .exclusive = true })) |second| {
        second.close(io);
    } else |err| switch (err) {
        error.PathAlreadyExists => sensitive = false,
        else => return err,
    }
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var output: std.Io.Writer.Allocating = .init(arena.allocator());
    fixture.reference = try content.writeTar(arena.allocator(), io, .{ .entries = &.{
        .{ .path = "A", .body = .bytes("upper") },
        .{ .path = "a", .body = .bytes("lower") },
    } }, &output.writer, .{});
    fixture.tar = output.written();
    var host: platform.Host = .init(io, .{ .env = .{} });
    if (sensitive) {
        const installed = try kernel.run(try fixture.options(&host, .install));
        try std.testing.expectEqual(@as(usize, 2), installed.state.?.roots[0].resources.len);
    } else {
        try std.testing.expectError(
            error.AccessExists,
            kernel.run(
                try fixture.options(
                    &host,
                    .install,
                ),
            ),
        );
        var options = try fixture.options(&host, .recover);
        options.model = null;
        const recovered = try kernel.run(options);
        try std.testing.expect(recovered.state == null);
    }
}

test "N2-KERNEL-05: state cannot cross selectors or library identities" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{} });
    const installed = try kernel.run(try fixture.options(&host, .install));
    try std.testing.expect(installed.state != null);
    fixture.version = 2;
    var options = try fixture.options(&host, .update);
    var model = options.model.?;
    const calls = try arena.allocator().dupe(program.model.Call, model.calls);
    calls[0].function = "other";
    model.calls = calls;
    options.model = model;
    try std.testing.expectError(error.KernelUpgrade, kernel.run(options));
}
