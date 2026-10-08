//! Inspect the actual component type before any guest can be instantiated.
const std = @import("std");
const engine = @import("component_engine");
const c = engine.c;

pub fn check(session: *engine.Session) !void {
    const kind = try session.componentType();
    defer c.wasmtime_component_type_delete(kind);
    try std.testing.expectEqual(
        @as(usize, 1),
        c.wasmtime_component_type_import_count(kind, session.engine),
    );
    var name: ?[*]const u8 = null;
    var name_len: usize = 0;
    var import: ?*c.Extern = null;
    try std.testing.expect(c.wasmtime_component_type_import_nth(
        kind,
        session.engine,
        0,
        &name,
        &name_len,
        &import,
    ));
    defer c.wasmtime_component_extern_delete(import.?);
    try std.testing.expectEqualStrings("niobium:qualification/host@0.1.0", name.?[0..name_len]);
    var exported: ?*c.Extern = null;
    const interface = "niobium:qualification/guest@0.1.0";
    try std.testing.expect(c.wasmtime_component_type_export_get(
        kind,
        session.engine,
        interface,
        interface.len,
        &exported,
    ));
    defer c.wasmtime_component_extern_delete(exported.?);
    var item: c.Item = undefined;
    c.wasmtime_component_extern_type(exported.?, &item);
    defer c.wasmtime_component_item_delete(&item);
    try std.testing.expectEqual(@as(u8, 1), item.kind);
    var function: ?*c.Extern = null;
    try std.testing.expect(c.wasmtime_component_instance_type_export_get(
        item.of.component_instance,
        session.engine,
        "evaluate",
        8,
        &function,
    ));
    defer c.wasmtime_component_extern_delete(function.?);
    var function_item: c.Item = undefined;
    c.wasmtime_component_extern_type(function.?, &function_item);
    defer c.wasmtime_component_item_delete(&function_item);
    try std.testing.expectEqual(@as(u8, 3), function_item.kind);
    try std.testing.expect(!c.wasmtime_component_func_type_async(function_item.of.component_func));
    try request(function_item.of.component_func);
}

fn request(func: *c.FuncType) !void {
    try std.testing.expectEqual(@as(usize, 1), c.wasmtime_component_func_type_param_count(func));
    var name: ?[*]const u8 = null;
    var len: usize = 0;
    var parameter: c.ValType = undefined;
    try std.testing.expect(c.wasmtime_component_func_type_param_nth(
        func,
        0,
        &name,
        &len,
        &parameter,
    ));
    defer c.wasmtime_component_valtype_delete(&parameter);
    try std.testing.expectEqualStrings("input", name.?[0..len]);
    try std.testing.expectEqual(@as(u8, 14), parameter.kind);
    try std.testing.expectEqual(
        @as(usize, 3),
        c.wasmtime_component_record_type_field_count(parameter.of.record),
    );
    var values: c.ValType = undefined;
    try std.testing.expect(c.wasmtime_component_record_type_field_nth(
        parameter.of.record,
        1,
        &name,
        &len,
        &values,
    ));
    defer c.wasmtime_component_valtype_delete(&values);
    try std.testing.expectEqualStrings("values", name.?[0..len]);
    try std.testing.expectEqual(@as(u8, 13), values.kind);
    var element: c.ValType = undefined;
    c.wasmtime_component_list_type_element(values.of.list, &element);
    defer c.wasmtime_component_valtype_delete(&element);
    try std.testing.expectEqual(@as(u8, 7), element.kind);
    var result: c.ValType = undefined;
    try std.testing.expect(c.wasmtime_component_func_type_result(func, &result));
    defer c.wasmtime_component_valtype_delete(&result);
    try std.testing.expectEqual(@as(u8, 19), result.kind);
}
