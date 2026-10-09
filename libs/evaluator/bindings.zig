//! Resolve the frozen call DAG without author evaluation or implicit dependency lookup.
const std = @import("std");
const program = @import("program");
const contracts = @import("contracts");
const kernel = @import("kernel");
const Value = program.value.Value;
pub const Result = struct { id: []const u8, value: Value };
pub const Error = program.value.Error || error{BindingMissing};
pub const Resolver = struct {
    arena: std.mem.Allocator,
    inputs: []const kernel.Input,
    results: []const Result,
    observations: []const Result,
    previous: Value,
    nodes: u32 = 0,

    pub fn resolve(self: *Resolver, binding: program.model.Binding, depth: u8) Error!Value {
        if (depth >= contracts.limits.default.component_depth or
            self.nodes >= contracts.limits.default.component_types) return error.ValueLimit;
        self.nodes += 1;
        return switch (binding) {
            .literal => |value| value,
            .input => |id| (program.find(kernel.Input, self.inputs, id) orelse
                return error.BindingMissing).value,
            .node_result => |ref| projection(self.results, ref),
            .observation => |ref| projection(self.observations, ref),
            .previous_state => self.previous,
            .record => |fields| blk: {
                const values = try self.arena.alloc(program.value.Field, fields.len);
                for (fields, values) |field, *value| value.* = .{
                    .name = field.name,
                    .value = try self.resolve(field.binding, depth + 1),
                };
                break :blk .{ .record = values };
            },
            .list => |items| .{ .list = try self.sequence(items, depth + 1) },
            .tuple => |items| .{ .tuple = try self.sequence(items, depth + 1) },
            .some => |item| blk: {
                const value = try self.arena.create(Value);
                value.* = try self.resolve(item.*, depth + 1);
                break :blk .{ .option = value };
            },
        };
    }

    fn sequence(self: *Resolver, items: []const program.model.Binding, depth: u8) Error![]Value {
        if (items.len > contracts.limits.default.component_types) return error.ValueLimit;
        const values = try self.arena.alloc(Value, items.len);
        for (items, values) |item, *value| value.* = try self.resolve(item, depth);
        return values;
    }
};

fn projection(items: []const Result, ref: program.model.Projection) Error!Value {
    const result = program.find(Result, items, ref.id) orelse return error.BindingMissing;
    return program.value.select(result.value, ref.fields);
}

test "N2-EVAL-01: typed projections and aggregates preserve values" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var resolver: Resolver = .{
        .arena = arena.allocator(),
        .inputs = &.{.{ .id = "enabled", .value = .{ .boolean = true } }},
        .results = &.{.{ .id = "producer", .value = .{ .record = &.{
            .{ .name = "count", .value = .{ .uint64 = std.math.maxInt(u64) } },
        } } }},
        .observations = &.{},
        .previous = .{ .option = null },
    };
    const result = try resolver.resolve(.{ .record = &.{
        .{ .name = "enabled", .binding = .{ .input = "enabled" } },
        .{ .name = "number", .binding = .{ .node_result = .{
            .id = "producer",
            .fields = &.{"count"},
        } } },
    } }, 0);
    try std.testing.expect((try program.value.select(result, &.{"enabled"})).boolean);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        (try program.value.select(result, &.{"number"})).uint64,
    );
    try std.testing.expectError(error.BindingMissing, resolver.resolve(.{ .input = "unknown" }, 0));
}
