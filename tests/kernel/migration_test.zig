//! An applied migration's identity is immutable even when the converter is not selected.
const std = @import("std");
const kernel = @import("kernel");
const program = @import("program");
const platform = @import("platform");
const Fixture = @import("fixture.zig").Fixture;
const io = std.testing.io;
const changed_digest = "1111111111111111111111111111111111111111111111111111111111111111";

test "N2-KERNEL-20: applied converter checksum cannot change on an otherwise stable version" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{}, .system_managers = false });
    const first = try kernel.run(try fixture.options(&host, .install));
    try std.testing.expect(first.state != null);
    fixture.version = 2;
    const second = try kernel.run(try fixture.options(&host, .update));
    try std.testing.expectEqual(@as(usize, 1), second.state.?.migrations.len);
    var options = try fixture.options(&host, .update);
    var model = options.model.?;
    model.release_sequence = 3;
    const libraries = try arena.allocator().dupe(program.model.Library, model.libraries);
    libraries[0].sha256 = changed_digest;
    model.libraries = libraries;
    const calls = try arena.allocator().dupe(program.model.Call, model.calls);
    const rules = try arena.allocator().dupe(program.model.Migration, calls[0].migrations);
    rules[0].implementation_sha256 = changed_digest;
    calls[0].migrations = rules;
    model.calls = calls;
    options.model = model;
    const before = fixture.evaluations;
    try std.testing.expectError(error.KernelUpgrade, kernel.run(options));
    try std.testing.expectEqual(before, fixture.evaluations);
    calls[0].migrations = &.{};
    const retired = try kernel.run(options);
    try std.testing.expectEqualStrings(
        second.state.?.migrations[0].rule.implementation_sha256,
        retired.state.?.migrations[0].rule.implementation_sha256,
    );
}

test "N2-KERNEL-20: product migration identity cannot be reused for a different edge" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fixture = try Fixture.init(arena.allocator(), io, tmp.dir, 1);
    var host: platform.Host = .init(io, .{ .env = .{}, .system_managers = false });
    const first = try kernel.run(try fixture.options(&host, .install));
    try std.testing.expect(first.state != null);
    fixture.version = 2;
    var options = try fixture.options(&host, .update);
    var model = options.model.?;
    model.model_version = 2;
    model.upgrades = &.{.{ .id = "schema-edge", .from = 1, .to = 2 }};
    options.model = model;
    const second = try kernel.run(options);
    try std.testing.expectEqual(@as(usize, 1), second.state.?.model_migrations.len);
    model.release_sequence = 3;
    model.model_version = 3;
    model.upgrades = &.{.{ .id = "schema-edge", .from = 2, .to = 3 }};
    options.model = model;
    const before = fixture.evaluations;
    try std.testing.expectError(error.KernelUpgrade, kernel.run(options));
    try std.testing.expectEqual(before, fixture.evaluations);
}
