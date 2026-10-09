//! Complete compiled input types are checked even when no Component argument uses them.
const std = @import("std");
const kernel = @import("kernel");
const program = @import("program");
const platform = @import("platform");
const Fixture = @import("fixture.zig").Fixture;
const io = std.testing.io;

test "N2-KERNEL-19: unused typed overrides fail before claiming a root" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{}, .system_managers = false });
    var options = try fixture.options(&host, .install);
    options.inputs = &.{.{ .id = "label", .value = .{ .boolean = true } }};
    try std.testing.expectError(error.WitTypeMismatch, kernel.run(options));
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(
            io,
            fixture.roots[0].path,
            .{},
        ),
    );
}

test "N2-KERNEL-19: record input rejects extra fields before claiming a root" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{}, .system_managers = false });
    var options = try fixture.options(&host, .install);
    var model = options.model.?;
    model.inputs = &.{
        .{
            .id = "label",
            .default = .{
                .record = &.{
                    .{
                        .name = "enabled",
                        .value = .{
                            .boolean = true,
                        },
                    },
                },
            },
            .resolved_type = .{
                .record = &.{
                    .{
                        .name = "enabled",
                        .ty = .boolean,
                    },
                },
            },
        },
    };
    options.model = model;
    options.inputs = &.{.{ .id = "label", .value = .{ .record = &.{
        .{ .name = "enabled", .value = .{ .boolean = true } },
        .{ .name = "extra", .value = .{ .text = "unrecognized" } },
    } } }};
    try std.testing.expectError(error.WitTypeMismatch, kernel.run(options));
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(
            io,
            fixture.roots[0].path,
            .{},
        ),
    );
}

test "N2-KERNEL-19: persisted reused input type is checked before lock creation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{}, .system_managers = false });
    const installed = try kernel.run(try fixture.options(&host, .install));
    var state = installed.state.?;
    state.inputs = &.{.{ .id = "label", .value = .{ .boolean = true } }};
    const path = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path, ".niobium-v2", "installation.json",
        },
    );
    const bytes = try std.json.Stringify.valueAlloc(arena.allocator(), state, .{});
    try host.platform().writeFile(path, bytes, false);
    const lock = try std.fs.path.join(
        arena.allocator(),
        &.{
            fixture.roots[0].path, ".niobium-lock",
        },
    );
    try std.Io.Dir.cwd().deleteFile(io, lock);
    try std.testing.expectError(
        error.WitTypeMismatch,
        kernel.run(
            try fixture.options(
                &host,
                .repair,
            ),
        ),
    );
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, lock, .{}));
    const retained = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        arena.allocator(),
        .limited(
            1 << 20,
        ),
    );
    try std.testing.expectEqualStrings(bytes, retained);
}

test "N2-KERNEL-19: wire string limits reject otherwise typed override before root claim" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{}, .system_managers = false });
    const text = try arena.allocator().alloc(u8, 131073);
    @memset(text, 'x');
    var options = try fixture.options(&host, .install);
    options.inputs = &.{.{ .id = "label", .value = .{ .text = text } }};
    try std.testing.expectError(error.JsonStringTooLong, kernel.run(options));
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(
            io,
            fixture.roots[0].path,
            .{},
        ),
    );
}
