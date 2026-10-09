//! Versioned observation contracts. Product consequences remain in capability libraries.
const std = @import("std");
const builtin = @import("builtin");
const program = @import("program");
const Value = program.value.Value;
const wit = program.wit;
pub const Error = program.profile.Error || program.value.Error || error{PrimitiveUnsupported};
pub const Interface = struct {
    primitive: program.profile.Requirement,
    interface: []const u8,
    functions: []const wit.NamedItem,
};
const facts_type: wit.Type = .{ .record = &.{
    .{ .name = "os", .ty = .text }, .{ .name = "architecture", .ty = .text },
} };
pub const interfaces: []const Interface = &.{.{
    .primitive = .{ .id = "machine.facts", .version = 1 },
    .interface = "niobium:host/machine@1.0.0",
    .functions = &.{.{ .name = "facts", .item = .{ .function = .{
        .params = &.{},
        .result = &facts_type,
    } } }},
}};
pub const primitives: []const program.profile.Requirement = &.{
    .{ .id = "content.tree", .version = 1 },
    .{ .id = "machine.facts", .version = 1 },
};

pub fn runtimeProfile(target: program.profile.Target) program.profile.Profile {
    return .{ .id = "niobium.user.component", .target = target, .primitives = primitives };
}

pub fn currentTarget() Error!program.profile.Target {
    const arch = builtin.cpu.arch;
    return switch (builtin.os.tag) {
        .macos => if (arch == .aarch64) .@"aarch64-macos" else error.PrimitiveUnsupported,
        .windows => if (arch == .x86_64) .@"x86_64-windows" else error.PrimitiveUnsupported,
        .linux => if (arch == .x86_64) .@"x86_64-linux" else error.PrimitiveUnsupported,
        else => error.PrimitiveUnsupported,
    };
}

pub fn observe(observation: program.model.Observation) Error!Value {
    if (!std.mem.eql(u8, observation.primitive.id, "machine.facts") or
        observation.primitive.version != 1 or !std.mem.eql(u8, observation.function, "facts"))
        return error.PrimitiveUnsupported;
    if (observation.arguments.len != 0 or observation.grant != null) return error.ValueInvalid;
    return .{ .record = &.{
        .{ .name = "os", .value = .{ .text = @tagName(builtin.os.tag) } },
        .{ .name = "architecture", .value = .{ .text = @tagName(builtin.cpu.arch) } },
    } };
}

test "N2-PRIMITIVE-01: facts are typed observations and unsupported requests stay explicit" {
    const fact = try observe(.{
        .id = "machine",
        .primitive = .{ .id = "machine.facts", .version = 1 },
        .function = "facts",
    });
    try wit.validateValue(fact, facts_type);
    try std.testing.expectEqualStrings(
        @tagName(builtin.os.tag),
        (try program.value.select(fact, &.{"os"})).text,
    );
    try std.testing.expectError(error.PrimitiveUnsupported, observe(.{
        .id = "machine",
        .primitive = .{ .id = "machine.facts", .version = 2 },
        .function = "facts",
    }));
}
