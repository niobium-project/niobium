//! Version-two semantics and graph checks shared by every authoring language.

const std = @import("std");
const model = @import("model.zig");
const program = @import("root.zig");

fn product() model.Product {
    return .{
        .id = "sample",
        .release_sequence = 1,
        .target = .@"aarch64-macos",
        .profile = .{
            .id = "runtime.user",
            .target = .@"aarch64-macos",
            .primitives = &.{.{ .id = "content.tree", .version = 1 }},
        },
        .libraries = &.{
            .{
                .id = "library",
                .member = "library.wasm",
                .sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                .bytes = 8,
            },
        },
        .inputs = &.{.{ .id = "choice", .default = .{ .text = "hello" } }},
        .roots = &.{.{ .id = "install" }},
        .state_root = "install",
        .grants = &.{
            .{
                .id = "files",
                .root = "install",
                .primitive = .{ .id = "content.tree", .version = 1 },
            },
        },
    };
}

test "N2-MODEL-01 v2 normalization preserves typed binding order and graph semantics" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var value = product();
    const one: model.Call = .{
        .id = "z",
        .library = "library",
        .interface = "example:api/test@1.0.0",
        .function = "one",
        .arguments = &.{
            .{ .literal = .{ .uint64 = std.math.maxInt(u64) } }, .{ .input = "choice" },
        },
    };
    const two: model.Call = .{
        .id = "a",
        .library = "library",
        .interface = "",
        .function = "two",
        .arguments = &.{.{ .node_result = .{ .id = "z", .fields = &.{"name"} } }},
    };
    value.calls = &.{ two, one };
    const bytes = try model.encode(a, value);
    const decoded = try model.decode(a, bytes);
    try std.testing.expectEqualStrings(bytes, try model.encode(a, decoded));
    const order = try model.order(a, decoded);
    try std.testing.expectEqualStrings("z", decoded.calls[order[0]].id);
    try std.testing.expectEqualStrings("a", decoded.calls[order[1]].id);
    const call = program.find(model.Call, decoded.calls, "z").?;
    try std.testing.expectEqual(std.math.maxInt(u64), call.arguments[0].literal.uint64);
    try std.testing.expectEqualStrings("choice", call.arguments[1].input);
}

test "N2-MODEL-02 invalid graph references cycles targets and authority fail" {
    var value = product();
    var calls = [_]model.Call{
        .{
            .id = "one",
            .library = "library",
            .interface = "",
            .function = "one",
            .after = &.{"two"},
        },
        .{
            .id = "two",
            .library = "library",
            .interface = "",
            .function = "two",
            .after = &.{"one"},
        },
    };
    value.calls = &calls;
    try std.testing.expectError(error.ProgramCycle, model.validate(value));
    calls[1].after = &.{"missing"};
    try std.testing.expectError(error.ProgramReference, model.validate(value));
    value.calls = &.{};
    value.target = .@"x86_64-linux";
    try std.testing.expectError(error.ProfileMismatch, model.validate(value));
    value.target = .@"aarch64-macos";
    value.roots = &.{.{ .id = "install", .scope = .machine }};
    try std.testing.expectError(error.ProgramUnsupported, model.validate(value));
    value.roots = &.{.{ .id = "install" }};
    var grants = [_]model.Grant{value.grants[0]};
    value.grants = &grants;
    grants[0].primitive.version = 2;
    try std.testing.expectError(error.ProfileMismatch, model.validate(value));
}

test "N2-MODEL-02 migrations name a fixed matching implementation" {
    var value = product();
    var rules = [_]model.Migration{.{
        .id = "state-1-2",
        .from = 1,
        .to = 2,
        .library = "library",
        .interface = "",
        .function = "migrate",
        .implementation_sha256 = value.libraries[0].sha256,
    }};
    var calls = [_]model.Call{.{
        .id = "instance",
        .library = "library",
        .interface = "",
        .function = "plan",
        .state_version = 2,
        .migrations = &rules,
        .result_role = .plan,
        .arguments = &.{.previous_state},
    }};
    value.calls = &calls;
    try model.validate(value);
    rules[0].implementation_sha256 =
        "0000000000000000000000000000000000000000000000000000000000000000";
    try std.testing.expectError(error.ProgramDigest, model.validate(value));
}

fn allocationCase(gpa: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try model.encode(a, product());
    const decoded = try model.decode(a, bytes);
    try std.testing.expectEqualStrings("sample", decoded.id);
}

test "N2-MODEL-02 v2 parser and normalization allocation failures propagate" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

test "N2-MODEL-03 aggregate bindings normalize records and preserve nested dependencies" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var value = product();
    var fields = [_]model.BindingField{
        .{ .name = "z", .binding = .{ .input = "choice" } },
        .{ .name = "a", .binding = .{ .some = &.{ .node_result = .{ .id = "z" } } } },
    };
    var calls = [_]model.Call{
        .{
            .id = "a",
            .library = "library",
            .interface = "",
            .function = "consume",
            .arguments = &.{.{ .record = &fields }},
        },
        .{ .id = "z", .library = "library", .interface = "", .function = "produce" },
    };
    value.calls = &calls;
    const before = try model.encode(a, value);
    std.mem.swap(model.BindingField, &fields[0], &fields[1]);
    try std.testing.expectEqualStrings(before, try model.encode(a, value));
    const order = try model.order(a, value);
    try std.testing.expectEqualStrings("z", value.calls[order[0]].id);
    calls[1].arguments = &.{.{ .list = &.{.{ .node_result = .{ .id = "a" } }} }};
    try std.testing.expectError(error.ProgramCycle, model.validate(value));
}

test "N2-MODEL-03 cyclic native aggregates and shared value budgets reject before encoding" {
    var cycle: model.Binding = .previous_state;
    cycle = .{ .some = &cycle };
    try std.testing.expectError(
        error.ProgramLimit,
        model.checking.validateBindingShape(cycle, .{}),
    );
    var repeated: [8]model.Binding = @splat(.{ .literal = .{ .text = "abc" } });
    try std.testing.expectError(
        error.ValueLimit,
        model.checking.validateBindingShape(.{ .list = &repeated }, .{ .program_bytes = 20 }),
    );
    var value = product();
    value.state_root = "";
    try std.testing.expectError(error.ProgramReference, model.validate(value));
}
