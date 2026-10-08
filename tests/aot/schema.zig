//! Structural schema conformance for the public model and durable runtime wire records.
const std = @import("std");
const program = @import("program");
const state = @import("runtime").state;
const Value = std.json.Value;

const Node = struct { document: Value, value: Value };
const Schemas = struct {
    program: Value,
    state: Value,
    plan: Value,

    fn load(allocator: std.mem.Allocator) !Schemas {
        return .{
            .program = try loadFile(allocator, "compiled-program-v1.schema.json"),
            .state = try loadFile(allocator, "runtime-state-v1.schema.json"),
            .plan = try loadFile(allocator, "runtime-plan-v1.schema.json"),
        };
    }

    fn resolve(self: Schemas, initial: Node) !Node {
        var node = initial;
        for (0..8) |_| {
            const reference = node.value.object.get("$ref") orelse return node;
            const separator = std.mem.indexOfScalar(u8, reference.string, '#');
            const uri = reference.string[0 .. separator orelse reference.string.len];
            const fragment = if (separator) |index| reference.string[index + 1 ..] else "";
            if (uri.len > 0) {
                node.document = for ([_]Value{ self.program, self.state, self.plan }) |candidate| {
                    const id = candidate.object.get("$id") orelse return error.SchemaMissing;
                    if (std.mem.eql(u8, id.string, uri)) break candidate;
                } else return error.SchemaReference;
            }
            if (fragment.len == 0) {
                node.value = node.document;
            } else {
                const prefix = "/$defs/";
                if (!std.mem.startsWith(u8, fragment, prefix)) return error.SchemaReference;
                const definitions = node.document.object.get("$defs") orelse
                    return error.SchemaMissing;
                node.value = definitions.object.get(fragment[prefix.len..]) orelse
                    return error.SchemaReference;
            }
        }
        return error.SchemaReference;
    }
};

fn loadFile(allocator: std.mem.Allocator, name: []const u8) !Value {
    const path = try allocator.print("api/schema/{s}", .{name});
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        path,
        allocator,
        .limited(1 << 20),
    );
    return std.json.parseFromSliceLeaky(Value, allocator, bytes, .{ .parse_numbers = false });
}

fn fields(comptime T: type, node: Value) !std.json.ObjectMap {
    const properties = node.object.get("properties") orelse return error.SchemaMissing;
    const closed = node.object.get("additionalProperties") orelse return error.SchemaMissing;
    try std.testing.expect(closed == .bool);
    try std.testing.expect(!closed.bool);
    try std.testing.expect(properties.object.count() == std.meta.fieldNames(T).len);
    inline for (comptime std.meta.fieldNames(T)) |name| {
        try std.testing.expect(properties.object.contains(name));
    }
    return properties.object;
}

fn required(node: Value, name: []const u8) bool {
    const list = node.object.get("required") orelse return false;
    for (list.array.items) |item| {
        if (std.mem.eql(u8, item.string, name)) return true;
    }
    return false;
}

fn fieldType(comptime T: type, schemas: Schemas, initial: Node) !void {
    const node = try schemas.resolve(initial);
    if (@typeInfo(T) == .optional) {
        const alternatives = node.value.object.get("anyOf") orelse return error.SchemaMissing;
        var found_null = false;
        var found_value = false;
        for (alternatives.array.items) |alternative| {
            if (alternative.object.get("type")) |kind| {
                if (std.mem.eql(u8, kind.string, "null")) found_null = true;
            } else {
                try object(@typeInfo(T).optional.child, schemas, .{
                    .document = node.document,
                    .value = alternative,
                });
                found_value = true;
            }
        }
        try std.testing.expect(found_null and found_value);
        return;
    }
    if (@typeInfo(T) == .int) {
        if (node.value.object.contains("const")) return;
        try expectKind(node.value, "integer");
        const maximum = node.value.object.get("maximum") orelse return error.SchemaMissing;
        var buffer: [32]u8 = undefined; // SAFETY: bufPrint writes the returned slice.
        const expected = try std.fmt.bufPrint(&buffer, "{d}", .{std.math.maxInt(T)});
        try std.testing.expectEqualStrings(expected, maximum.number_string);
        return;
    }
    if (T == []const u8) {
        if (node.value.object.get("anyOf")) |alternatives| {
            for (alternatives.array.items) |alternative| {
                const branch = try schemas.resolve(.{
                    .document = node.document,
                    .value = alternative,
                });
                try stringKind(branch.value);
            }
            return;
        }
        return stringKind(node.value);
    }
    const child = @typeInfo(T).pointer.child;
    try expectKind(node.value, "array");
    const items = try schemas.resolve(.{
        .document = node.document,
        .value = node.value.object.get("items") orelse return error.SchemaMissing,
    });
    if (child == []const u8) return expectKind(items.value, "string");
    const child_fields = try fields(child, items.value);
    try std.testing.expect(child_fields.count() > 0);
}

fn stringKind(node: Value) !void {
    if (node.object.get("const")) |literal| {
        try std.testing.expect(literal == .string);
        return;
    }
    return expectKind(node, "string");
}

fn expectKind(node: Value, expected: []const u8) !void {
    const kind = node.object.get("type") orelse return error.SchemaMissing;
    try std.testing.expectEqualStrings(expected, kind.string);
}

fn object(comptime T: type, schemas: Schemas, initial: Node) !void {
    const node = try schemas.resolve(initial);
    const properties = try fields(T, node.value);
    const metadata = @typeInfo(T).@"struct";
    inline for (
        metadata.field_names,
        metadata.field_types,
        metadata.field_attrs,
    ) |name, Type, attrs| {
        try fieldType(Type, schemas, .{
            .document = node.document,
            .value = properties.get(name) orelse return error.SchemaMissing,
        });
        if (attrs.default_value_ptr == null) try std.testing.expect(required(node.value, name));
    }
}

test "N2-AUTH-01: published program schema matches native wire fields and widths" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const schemas = try Schemas.load(allocator);
    const schema = schemas.program;
    try object(program.Program, schemas, .{ .document = schema, .value = schema });
    const definitions = schema.object.get("$defs").?.object;
    inline for (
        .{
            program.Input,    program.Library,  program.Asset,
            program.Resource, program.Instance, program.Migration,
        },
        .{ "input", "library", "asset", "resource", "instance", "migration" },
    ) |Type, name| try object(Type, schemas, .{
        .document = schema,
        .value = definitions.get(name).?,
    });
    const properties = schema.object.getPtr("properties").?;
    try properties.object.put(allocator, "undeclared_field", .null);
    try std.testing.expectError(error.TestUnexpectedResult, object(program.Program, schemas, .{
        .document = schema,
        .value = schema,
    }));
}

test "N2-SAFE-01: state and frozen-plan schemas match native wire types" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const schemas = try Schemas.load(arena.allocator());
    const snapshot = schemas.state;
    try object(state.Snapshot, schemas, .{ .document = snapshot, .value = snapshot });
    const definitions = snapshot.object.get("$defs").?.object;
    inline for (
        .{ state.Owner, state.Value, state.Instance, state.Migration, state.Resource },
        .{ "owner", "value", "instance", "migration", "resource" },
    ) |Type, name| try object(Type, schemas, .{
        .document = snapshot,
        .value = definitions.get(name).?,
    });
    const plan = schemas.plan;
    try object(state.Plan, schemas, .{ .document = plan, .value = plan });
    try object(state.File, schemas, .{
        .document = plan,
        .value = plan.object.get("$defs").?.object.get("file").?,
    });
}
