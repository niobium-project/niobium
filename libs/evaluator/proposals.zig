//! Canonicalize guest content under host ownership before returning durable resource identities.
const std = @import("std");
const root = @import("root.zig");
const program = @import("program");
const contracts = @import("contracts");
const content = @import("content");
const kernel = @import("kernel");
const v = root.values;
const Value = program.value.Value;

pub fn freeze(
    context: *root.Context,
    arena: std.mem.Allocator,
    io: std.Io,
    call: program.model.Call,
    plan: Value,
    desired: *std.ArrayList(kernel.DesiredContainer),
) root.Error!Value {
    try program.value.validate(plan, .{});
    const proposals = try v.field(plan, "containers");
    const state = try v.field(plan, "state");
    if (proposals != .list or state != .option or
        proposals.list.len > contracts.limits.default.program_items - desired.items.len)
        return error.ValueInvalid;
    const normalized = try arena.alloc(Value, proposals.list.len);
    for (proposals.list, normalized) |proposal, *stored| {
        const source = try v.field(proposal, "container");
        if (source != .variant) return error.ValueInvalid;
        const payload = (source.variant.payload orelse return error.ValueInvalid).*;
        const reference = if (std.mem.eql(u8, source.variant.name, "reference"))
            try v.reference(arena, payload)
        else if (std.mem.eql(u8, source.variant.name, "generated"))
            try generate(context, arena, io, payload)
        else
            return error.ValueInvalid;
        if (context.findContent(reference) == null) return error.LibraryMissing;
        try desired.append(arena, .{
            .call = call.id,
            .root = try v.string(try v.field(proposal, "root")),
            .grant = try v.string(try v.field(proposal, "grant")),
            .prefix = try v.string(try v.field(proposal, "prefix")),
            .container = reference,
            .file_access = try v.policy(try v.field(proposal, "file-access"), .file),
            .directory_access = try v.policy(try v.field(proposal, "directory-access"), .directory),
        });
        const fields = try arena.dupe(program.value.Field, proposal.record);
        for (fields) |*field| {
            if (std.mem.eql(u8, field.name, "container")) {
                field.value = try asValue(arena, reference);
            }
        }
        stored.* = .{ .record = fields };
    }
    const fields = try arena.dupe(program.value.Field, plan.record);
    for (fields) |*field| {
        if (std.mem.eql(u8, field.name, "containers")) field.value = .{ .list = normalized };
    }
    return .{ .record = fields };
}

fn generate(
    context: *root.Context,
    arena: std.mem.Allocator,
    io: std.Io,
    entries: Value,
) root.Error!content.ContainerRef {
    const tree = try v.tree(arena, entries);
    if (context.scratch == null) {
        context.scratch = try arena.alloc(u8, contracts.limits.default.generated_container_bytes);
    }
    var writer: std.Io.Writer = .fixed(context.scratch.?);
    const reference = try content.writeTar(arena, io, tree, &writer, .{});
    if (context.findContent(reference) != null) return reference;
    if (reference.bytes > contracts.limits.default.evaluation_content_bytes -
        context.generated_bytes) return error.KernelLimit;
    context.generated_bytes += reference.bytes;
    const owned = try arena.dupe(u8, writer.buffered());
    try context.generated.append(arena, .{
        .reference = reference,
        .body = content.Body.bytes(owned),
    });
    return reference;
}

fn asValue(arena: std.mem.Allocator, reference: content.ContainerRef) root.Error!Value {
    const fields = try arena.dupe(program.value.Field, &.{
        .{ .name = "format", .value = .{ .enumeration = "posix-pax-v1" } },
        .{ .name = "bytes", .value = .{ .uint64 = reference.bytes } },
        .{ .name = "sha256", .value = .{ .bytes = try arena.dupe(u8, &reference.sha256) } },
    });
    const value = try arena.create(Value);
    value.* = .{ .record = fields };
    return .{ .variant = .{ .name = "reference", .payload = value } };
}

test "N2-EVAL-03: host plan normalization preserves additional typed downstream fields" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var context: root.Context = .{
        .executable = "/fixed-runtime",
        .libraries = &.{},
        .fixed_content = &.{},
    };
    var desired: std.ArrayList(kernel.DesiredContainer) = .empty;
    const call: program.model.Call = .{
        .id = "producer",
        .library = "library",
        .interface = "test:plan/producer@1.0.0",
        .function = "build",
        .result_role = .plan,
    };
    const normalized = try freeze(&context, a, std.testing.io, call, .{ .record = &.{
        .{ .name = "containers", .value = .{ .list = &.{} } },
        .{ .name = "state", .value = .{ .option = null } },
        .{ .name = "revision", .value = .{ .uint64 = std.math.maxInt(u64) } },
    } }, &desired);
    var resolver: root.bindings.Resolver = .{
        .arena = a,
        .inputs = &.{},
        .observations = &.{},
        .previous = .{ .option = null },
        .results = &.{.{ .id = "producer", .value = normalized }},
    };
    const value = try resolver.resolve(.{ .node_result = .{
        .id = "producer",
        .fields = &.{"revision"},
    } }, 0);
    try std.testing.expectEqual(std.math.maxInt(u64), value.uint64);
}
