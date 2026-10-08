//! Published runtime capabilities are data; build-host capabilities never select the target.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("root.zig");

pub const Error = program.Error || error{ProfileMismatch};
pub const Target = enum { @"x86_64-windows", @"aarch64-macos", @"x86_64-linux" };
pub const Requirement = struct { id: []const u8, version: u32 };
pub const Profile = struct {
    schema: u32 = 1,
    id: []const u8,
    target: Target,
    runtime_abi: u32 = 2,
    program_schema: u32 = 2,
    component_profile: u32 = 1,
    content_profile: u32 = 1,
    primitives: []const Requirement,
};

pub fn validate(value: Profile) Error!void {
    if (value.schema != 1 or value.runtime_abi != 2 or value.program_schema != 2 or
        value.component_profile != 1 or value.content_profile != 1)
        return error.ProgramUnsupported;
    try program.validation.identifier(value.id);
    try validateRequirements(value.primitives);
}

pub fn validateRequirements(items: []const Requirement) Error!void {
    if (items.len > (contracts.Limits{}).program_items) return error.ProgramLimit;
    for (items, 0..) |item, index| {
        try program.validation.identifier(item.id);
        if (item.version == 0) return error.ProgramInvalid;
        for (items[0..index]) |other| {
            if (std.mem.eql(u8, item.id, other.id)) return error.ProgramDuplicate;
        }
    }
}

pub fn require(value: Profile, target: Target, required: []const Requirement) Error!void {
    try validate(value);
    try validateRequirements(required);
    if (value.target != target) return error.ProfileMismatch;
    for (required) |item| {
        const provided = program.find(Requirement, value.primitives, item.id) orelse
            return error.ProfileMismatch;
        if (provided.version != item.version) return error.ProfileMismatch;
    }
}

pub fn decode(arena: std.mem.Allocator, bytes: []const u8) Error!Profile {
    const value = try contracts.json.decode(Profile, arena, bytes, .{
        .max_bytes = (contracts.Limits{}).manifest_bytes,
        .max_schema = 1,
    });
    try validate(value);
    return value;
}

test "N2-PROFILE-01: target and primitive versions never fall back" {
    const value: Profile = .{
        .id = "niobium.files.user",
        .target = .@"x86_64-windows",
        .primitives = &.{.{ .id = "content.tree", .version = 1 }},
    };
    try require(value, .@"x86_64-windows", value.primitives);
    try std.testing.expectError(error.ProfileMismatch, require(value, .@"aarch64-macos", &.{}));
    try std.testing.expectError(error.ProfileMismatch, require(value, value.target, &.{
        .{ .id = "content.tree", .version = 2 },
    }));
    try std.testing.expectError(error.ProfileMismatch, require(value, value.target, &.{
        .{ .id = "process.execute", .version = 1 },
    }));
}
