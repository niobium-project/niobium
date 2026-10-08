//! Reflection delegates WIT type interpretation to the pinned upstream Component C API.
const std = @import("std");
const program = @import("program");
const contracts = @import("contracts");
const engine = @import("component_engine");
const c = engine.c;
const wit = program.wit;
const Error = @import("root.zig").Error;
const limits: contracts.Limits = .{};

pub fn describe(arena: std.mem.Allocator, session: *engine.Session) Error!wit.Inspection {
    var state: State = .{ .arena = arena, .engine = session.engine };
    const component = try session.componentType();
    defer c.wasmtime_component_type_delete(component);
    return .{
        .imports = try state.world(component, true),
        .exports = try state.world(component, false),
    };
}

const State = struct {
    arena: std.mem.Allocator,
    engine: *c.Engine,
    nodes: u32 = 0,

    fn world(self: *State, component: *c.ComponentType, imports: bool) Error![]const wit.NamedItem {
        const count = if (imports)
            c.wasmtime_component_type_import_count(component, self.engine)
        else
            c.wasmtime_component_type_export_count(component, self.engine);
        if (count > limits.component_types) return error.WorkerLimit;
        const items = try self.arena.alloc(wit.NamedItem, count);
        for (items, 0..) |*item, index| {
            var name: ?[*]const u8 = null;
            var size: usize = 0;
            var external: ?*c.Extern = null;
            const success = if (imports) c.wasmtime_component_type_import_nth(
                component,
                self.engine,
                index,
                &name,
                &size,
                &external,
            ) else c.wasmtime_component_type_export_nth(
                component,
                self.engine,
                index,
                &name,
                &size,
                &external,
            );
            if (!success) return error.Engine;
            const imported = external orelse return error.Engine;
            defer c.wasmtime_component_extern_delete(imported);
            item.* = .{
                .name = try self.copyName(name, size),
                .item = try self.describeItem(imported, 0),
            };
        }
        return items;
    }

    fn describeItem(self: *State, external: *c.Extern, depth: u8) Error!wit.Item {
        try self.charge(depth);
        // SAFETY: The official C API initializes this output on the checked success path.
        var native: c.Item = undefined;
        c.wasmtime_component_extern_type(external, &native);
        defer c.wasmtime_component_item_delete(&native);
        return switch (native.kind) {
            1 => .{ .instance = try self.instance(native.of.component_instance, depth + 1) },
            3 => .{ .function = try self.function(native.of.component_func, depth + 1) },
            4 => .resource,
            6 => .{ .value_type = try self.valueType(native.of.value_type, depth + 1) },
            else => .{ .unsupported = native.kind },
        };
    }

    fn instance(self: *State, native: *c.InstanceType, depth: u8) Error![]const wit.NamedItem {
        const count = c.wasmtime_component_instance_type_export_count(native, self.engine);
        if (count > limits.component_types) return error.WorkerLimit;
        const items = try self.arena.alloc(wit.NamedItem, count);
        for (items, 0..) |*entry, index| {
            var name: ?[*]const u8 = null;
            var size: usize = 0;
            var external: ?*c.Extern = null;
            if (!c.wasmtime_component_instance_type_export_nth(
                native,
                self.engine,
                index,
                &name,
                &size,
                &external,
            )) return error.Engine;
            const child = external orelse return error.Engine;
            defer c.wasmtime_component_extern_delete(child);
            entry.* = .{
                .name = try self.copyName(name, size),
                .item = try self.describeItem(child, depth),
            };
        }
        return items;
    }

    fn function(self: *State, native: *c.FuncType, depth: u8) Error!wit.FunctionType {
        const count = c.wasmtime_component_func_type_param_count(native);
        if (count > limits.program_items) return error.WorkerLimit;
        const params = try self.arena.alloc(wit.FieldType, count);
        for (params, 0..) |*param, index| {
            var name: ?[*]const u8 = null;
            var size: usize = 0;
            // SAFETY: The official C API initializes this output on the checked success path.
            var ty: c.ValType = undefined;
            if (!c.wasmtime_component_func_type_param_nth(
                native,
                index,
                &name,
                &size,
                &ty,
            )) return error.Engine;
            defer c.wasmtime_component_valtype_delete(&ty);
            param.* = .{
                .name = try self.copyName(name, size),
                .ty = try self.valueType(ty, depth),
            };
        }
        // SAFETY: The official C API initializes this output on the checked success path.
        var result: c.ValType = undefined;
        const present = c.wasmtime_component_func_type_result(native, &result);
        defer if (present) c.wasmtime_component_valtype_delete(&result);
        return .{
            .params = params,
            .asynchronous = c.wasmtime_component_func_type_async(native),
            .result = if (present) try self.box(result, depth) else null,
        };
    }

    fn valueType(self: *State, ty: c.ValType, depth: u8) Error!wit.Type {
        try self.charge(depth);
        return switch (ty.kind) {
            0 => .boolean,
            1 => .sint8,
            2 => .sint16,
            3 => .sint32,
            4 => .sint64,
            5 => .uint8,
            6 => .uint16,
            7 => .uint32,
            8 => .uint64,
            9 => .float32,
            10 => .float64,
            11 => .character,
            12 => .text,
            13, 18 => try self.container(ty, depth + 1),
            14 => .{ .record = try self.record(ty.of.record, depth + 1) },
            15 => .{ .tuple = try self.tuple(ty.of.tuple, depth + 1) },
            16 => .{ .variant = try self.variant(ty.of.variant, depth + 1) },
            17 => .{ .enumeration = try self.labels(ty) },
            19 => .{ .result = try self.resultType(ty.of.result, depth + 1) },
            20 => .{ .flags = try self.labels(ty) },
            21 => .own_resource,
            22 => .borrow_resource,
            else => .{ .unsupported = ty.kind },
        };
    }

    fn container(self: *State, ty: c.ValType, depth: u8) Error!wit.Type {
        // SAFETY: The official C API initializes this output on the checked success path.
        var inner: c.ValType = undefined;
        if (ty.kind == 13) {
            c.wasmtime_component_list_type_element(ty.of.list, &inner);
        } else {
            c.wasmtime_component_option_type_ty(ty.of.option, &inner);
        }
        defer c.wasmtime_component_valtype_delete(&inner);
        const boxed = try self.box(inner, depth);
        return if (ty.kind == 13) .{ .list = boxed } else .{ .option = boxed };
    }

    fn record(self: *State, native: *c.RecordType, depth: u8) Error![]const wit.FieldType {
        const count = c.wasmtime_component_record_type_field_count(native);
        if (count > limits.program_items) return error.WorkerLimit;
        const fields = try self.arena.alloc(wit.FieldType, count);
        for (fields, 0..) |*field, index| {
            var name: ?[*]const u8 = null;
            var size: usize = 0;
            // SAFETY: The official C API initializes this output on the checked success path.
            var ty: c.ValType = undefined;
            if (!c.wasmtime_component_record_type_field_nth(
                native,
                index,
                &name,
                &size,
                &ty,
            )) return error.Engine;
            defer c.wasmtime_component_valtype_delete(&ty);
            field.* = .{
                .name = try self.copyName(name, size),
                .ty = try self.valueType(ty, depth),
            };
        }
        return fields;
    }

    fn tuple(self: *State, native: *c.TupleType, depth: u8) Error![]const wit.Type {
        const count = c.wasmtime_component_tuple_type_types_count(native);
        if (count > limits.program_items) return error.WorkerLimit;
        const items = try self.arena.alloc(wit.Type, count);
        for (items, 0..) |*item_type, index| {
            // SAFETY: The official C API initializes this output on the checked success path.
            var ty: c.ValType = undefined;
            if (!c.wasmtime_component_tuple_type_types_nth(native, index, &ty)) return error.Engine;
            defer c.wasmtime_component_valtype_delete(&ty);
            item_type.* = try self.valueType(ty, depth);
        }
        return items;
    }

    fn variant(self: *State, native: *c.VariantType, depth: u8) Error![]const wit.CaseType {
        const count = c.wasmtime_component_variant_type_case_count(native);
        if (count > limits.program_items) return error.WorkerLimit;
        const cases = try self.arena.alloc(wit.CaseType, count);
        for (cases, 0..) |*case, index| {
            var name: ?[*]const u8 = null;
            var size: usize = 0;
            // SAFETY: The official C API initializes this output on the checked success path.
            var ty: c.ValType = undefined;
            var present = false;
            if (!c.wasmtime_component_variant_type_case_nth(
                native,
                index,
                &name,
                &size,
                &present,
                &ty,
            )) return error.Engine;
            defer if (present) c.wasmtime_component_valtype_delete(&ty);
            case.* = .{
                .name = try self.copyName(name, size),
                .payload = if (present) try self.box(ty, depth) else null,
            };
        }
        return cases;
    }

    fn resultType(self: *State, native: *c.ResultType, depth: u8) Error!wit.ResultType {
        // SAFETY: The official C API initializes this output on the checked success path.
        var ok: c.ValType = undefined;
        // SAFETY: The official C API initializes this output on the checked success path.
        var err: c.ValType = undefined;
        const has_ok = c.wasmtime_component_result_type_ok(native, &ok);
        const has_err = c.wasmtime_component_result_type_err(native, &err);
        defer if (has_ok) c.wasmtime_component_valtype_delete(&ok);
        defer if (has_err) c.wasmtime_component_valtype_delete(&err);
        return .{
            .ok = if (has_ok) try self.box(ok, depth) else null,
            .err = if (has_err) try self.box(err, depth) else null,
        };
    }

    fn labels(self: *State, ty: c.ValType) Error![]const []const u8 {
        const count = if (ty.kind == 17)
            c.wasmtime_component_enum_type_names_count(ty.of.enumeration)
        else
            c.wasmtime_component_flags_type_names_count(ty.of.flags);
        if (count > limits.program_items) return error.WorkerLimit;
        const names = try self.arena.alloc([]const u8, count);
        for (names, 0..) |*label, index| {
            var name: ?[*]const u8 = null;
            var size: usize = 0;
            const success = if (ty.kind == 17) c.wasmtime_component_enum_type_names_nth(
                ty.of.enumeration,
                index,
                &name,
                &size,
            ) else c.wasmtime_component_flags_type_names_nth(
                ty.of.flags,
                index,
                &name,
                &size,
            );
            if (!success) return error.Engine;
            label.* = try self.copyName(name, size);
        }
        return names;
    }

    fn box(self: *State, ty: c.ValType, depth: u8) Error!*const wit.Type {
        const pointer = try self.arena.create(wit.Type);
        pointer.* = try self.valueType(ty, depth);
        return pointer;
    }

    fn copyName(self: *State, pointer: ?[*]const u8, size: usize) Error![]const u8 {
        if (size > 256) return error.WorkerLimit;
        if (size == 0) return "";
        return self.arena.dupe(u8, (pointer orelse return error.Engine)[0..size]);
    }

    fn charge(self: *State, depth: u8) Error!void {
        if (depth >= limits.component_depth or self.nodes >= limits.component_types)
            return error.WorkerLimit;
        self.nodes += 1;
    }
};
