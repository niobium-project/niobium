//! The shared model rejects invalid references before any compiler or runtime mutation.

const std = @import("std");
const root = @import("root.zig");

test "N2-PROFILE-01: resource profile rejects aliases and internal metadata subtrees" {
    try std.testing.expectError(error.ProgramPath, root.validation.resourcePath("café"));
    try std.testing.expectError(error.ProgramPath, root.validation.resourcePath("cafe\u{0301}"));
    try std.testing.expectError(
        error.ProgramPath,
        root.validation.resourcePath(".niobium-generation/file"),
    );
    try std.testing.expect(root.validation.pathsConflict("share", "SHARE/file"));
}

test "N2-AUTH-02: input text is bounded in UTF-8 bytes" {
    try root.validation.inputValue("\u{e9}", .{ .program_state_bytes = 2 });
    try std.testing.expectError(error.ProgramLimit, root.validation.inputValue(
        "\u{e9}",
        .{ .program_state_bytes = 1 },
    ));
    try std.testing.expectError(error.ProgramInvalid, root.validation.inputValue("\xff", .{}));
}
