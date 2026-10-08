//! The shared model rejects invalid references before any compiler or runtime mutation.

const std = @import("std");
const root = @import("root.zig");

fn sample(arena: std.mem.Allocator) !root.Program {
    const libraries = try arena.alloc(root.Library, 1);
    libraries[0] = .{
        .id = "test.library",
        .sha256 = try root.digest(arena, "wasm"),
        .wasm_hex = try root.encodeHex(arena, "wasm"),
    };
    return .{
        .product_id = "example.product",
        .release_sequence = 1,
        .libraries = libraries,
        .inputs = &.{ .{ .id = "z", .default = "second" }, .{ .id = "a", .default = "first" } },
        .resources = &.{.{ .id = "environment", .path = "share/environment.txt" }},
        .instances = &.{.{
            .id = "environment",
            .library = "test.library",
            .inputs = &.{ "z", "a" },
            .resources = &.{"environment"},
        }},
    };
}

test "N2-AUTH-01: normalization sorts identities but preserves argument bindings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const value = try sample(arena.allocator());
    const bytes = try root.encode(arena.allocator(), value);
    const decoded = try root.decode(arena.allocator(), bytes);
    try std.testing.expectEqualStrings("a", decoded.inputs[0].id);
    try std.testing.expectEqualStrings("z", decoded.instances[0].inputs[0]);
    try std.testing.expectEqualStrings(bytes, try root.encode(arena.allocator(), decoded));
}

test "N2-AUTH-01: absent references, unsafe paths and duplicate owners fail" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var value = try sample(arena.allocator());
    value.resources = &.{.{ .id = "other", .path = "safe.txt" }};
    try std.testing.expectError(error.ProgramReference, root.validate(value));
    value.resources = &.{.{ .id = "environment", .path = "../outside" }};
    try std.testing.expectError(error.ProgramPath, root.validate(value));
    value.resources = &.{.{ .id = "environment", .path = "safe.txt" }};
    value.instances = &.{
        .{ .id = "one", .library = "test.library", .resources = &.{"environment"} },
        .{ .id = "two", .library = "test.library", .resources = &.{"environment"} },
    };
    try std.testing.expectError(error.ProgramDuplicate, root.validate(value));
}

test "N2-LIB-01: blob identities bind the actual library bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var value = try sample(arena.allocator());
    value.libraries = &.{.{
        .id = "test.library",
        .sha256 = try root.digest(arena.allocator(), "different"),
        .wasm_hex = try root.encodeHex(arena.allocator(), "wasm"),
    }};
    try std.testing.expectError(error.ProgramDigest, root.validate(value));
}

test "N2-SAFE-01: resource profile rejects aliases and internal metadata subtrees" {
    try std.testing.expectError(error.ProgramPath, root.validation.resourcePath("café"));
    try std.testing.expectError(error.ProgramPath, root.validation.resourcePath("cafe\u{0301}"));
    try std.testing.expectError(
        error.ProgramPath,
        root.validation.resourcePath(".niobium-generation/file"),
    );
    try std.testing.expect(root.validation.pathsConflict("share", "SHARE/file"));
}

test "N2-AUTH-01: a release may explicitly retire all capability instances" {
    try root.validate(.{ .product_id = "example.empty", .release_sequence = 3 });
}

test "N2-AUTH-01: input text is bounded in UTF-8 bytes" {
    try root.validation.inputValue("\u{e9}", .{ .program_state_bytes = 2 });
    try std.testing.expectError(error.ProgramLimit, root.validation.inputValue(
        "\u{e9}",
        .{ .program_state_bytes = 1 },
    ));
    try std.testing.expectError(error.ProgramInvalid, root.validation.inputValue("\xff", .{}));
}
