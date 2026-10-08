//! Handwritten declarations of the pinned upstream Component C API, not a guest ABI.
pub const Config = opaque {};
pub const Engine = opaque {};
pub const Store = opaque {};
pub const Context = opaque {};
pub const Error = opaque {};
pub const Component = opaque {};
pub const Linker = opaque {};
pub const LinkerInstance = opaque {};
pub const ExportIndex = opaque {};
pub const FuncType = opaque {};
pub const Resource = opaque {};
pub const ComponentType = opaque {};
pub const InstanceType = opaque {};
pub const Extern = opaque {};
pub const ListType = opaque {};
pub const RecordType = opaque {};
pub const VariantType = opaque {};
pub const OptionType = opaque {};
pub const ResultType = opaque {};
pub const TupleType = opaque {};
pub const EnumType = opaque {};
pub const FlagsType = opaque {};
pub const ValType = extern struct {
    kind: u8,
    of: extern union {
        pointer: ?*anyopaque,
        list: *ListType,
        record: *RecordType,
        variant: *VariantType,
        option: *OptionType,
        result: *ResultType,
        tuple: *TupleType,
        enumeration: *EnumType,
        flags: *FlagsType,
    },
};
pub const Item = extern struct {
    kind: u8,
    of: extern union {
        component: *ComponentType,
        component_instance: *InstanceType,
        component_func: *FuncType,
        pointer: ?*anyopaque,
        value_type: ValType,
    },
};

pub fn Vec(comptime T: type) type {
    return extern struct { size: usize, data: ?[*]T };
}
pub const Bytes = Vec(u8);
pub const Instance = extern struct { store_id: u64, private: u32 };
pub const Func = extern struct {
    store_id: u64,
    private1: u32,
    private2: u32,
    private3: ?*anyopaque,
};
pub const Variant = extern struct { discriminant: Bytes, val: ?*Val };
pub const Result = extern struct { is_ok: bool, val: ?*Val };
pub const Field = extern struct { name: Bytes, val: Val };
pub const Pair = extern struct { key: Val, value: Val };
pub const Val = extern struct {
    kind: u8,
    of: extern union {
        boolean: bool,
        s8: i8,
        u8: u8,
        s16: i16,
        u16: u16,
        s32: i32,
        u32: u32,
        s64: i64,
        u64: u64,
        f32: f32,
        f64: f64,
        character: u32,
        string: Bytes,
        list: Vec(Val),
        record: Vec(Field),
        tuple: Vec(Val),
        variant: Variant,
        enumeration: Bytes,
        option: ?*Val,
        result: Result,
        flags: Vec(Bytes),
        map: Vec(Pair),
        resource: ?*Resource,
    },
};
pub const bool_kind = 0;
pub const u32_kind = 6;
pub const u64_kind = 8;
pub const string_kind = 12;
pub const list_kind = 13;
pub const record_kind = 14;
pub const option_kind = 18;
pub const result_kind = 19;
pub const resource_kind = 21;
pub const Callback = *const fn (
    ?*anyopaque,
    *Context,
    *const FuncType,
    ?[*]Val,
    usize,
    ?[*]Val,
    usize,
) callconv(.c) ?*Error;

pub extern fn wasm_config_new() ?*Config;
pub extern fn wasm_config_delete(*Config) void;
pub extern fn wasm_engine_new_with_config(*Config) ?*Engine;
pub extern fn wasm_engine_delete(*Engine) void;
pub extern fn wasm_byte_vec_new(*Bytes, usize, [*]const u8) void;
pub extern fn wasm_byte_vec_delete(*Bytes) void;
pub extern fn wasmtime_config_target_set(*Config, [*:0]const u8) ?*Error;
pub extern fn wasmtime_config_consume_fuel_set(*Config, bool) void;
pub extern fn wasmtime_config_max_wasm_stack_set(*Config, usize) void;
pub extern fn wasmtime_config_memory_reservation_set(*Config, u64) void;
pub extern fn wasmtime_config_memory_reservation_for_growth_set(*Config, u64) void;
pub extern fn wasmtime_config_signals_based_traps_set(*Config, bool) void;
pub extern fn wasmtime_store_new(
    *Engine,
    ?*anyopaque,
    ?*const fn (?*anyopaque) callconv(.c) void,
) ?*Store;
pub extern fn wasmtime_store_delete(*Store) void;
pub extern fn wasmtime_store_context(*Store) *Context;
pub extern fn wasmtime_store_limiter(*Store, i64, i64, i64, i64, i64) void;
pub extern fn wasmtime_context_set_fuel(*Context, u64) ?*Error;
pub extern fn wasmtime_context_get_fuel(*Context, *u64) ?*Error;
pub extern fn wasmtime_error_new([*:0]const u8) *Error;
pub extern fn wasmtime_error_message(*const Error, *Bytes) void;
pub extern fn wasmtime_error_delete(*Error) void;
pub extern fn wasmtime_component_new(*Engine, [*]const u8, usize, *?*Component) ?*Error;
pub extern fn wasmtime_component_delete(*Component) void;
pub extern fn wasmtime_component_linker_new(*Engine) ?*Linker;
pub extern fn wasmtime_component_linker_delete(*Linker) void;
pub extern fn wasmtime_component_linker_root(*Linker) ?*LinkerInstance;
pub extern fn wasmtime_component_linker_instance_delete(*LinkerInstance) void;
pub extern fn wasmtime_component_linker_instance_add_instance(
    *LinkerInstance,
    [*]const u8,
    usize,
    *?*LinkerInstance,
) ?*Error;
pub extern fn wasmtime_component_linker_instance_add_func(
    *LinkerInstance,
    [*]const u8,
    usize,
    Callback,
    ?*anyopaque,
    ?*const fn (?*anyopaque) callconv(.c) void,
) ?*Error;
pub extern fn wasmtime_component_linker_instantiate(
    *Linker,
    *Context,
    *Component,
    *Instance,
) ?*Error;
pub extern fn wasmtime_component_instance_get_export_index(
    *const Instance,
    *Context,
    ?*const ExportIndex,
    [*]const u8,
    usize,
) ?*ExportIndex;
pub extern fn wasmtime_component_export_index_delete(*ExportIndex) void;
pub extern fn wasmtime_component_instance_get_func(
    *const Instance,
    *Context,
    *const ExportIndex,
    *Func,
) bool;
pub extern fn wasmtime_component_func_call(
    *const Func,
    *Context,
    ?[*]const Val,
    usize,
    ?[*]Val,
    usize,
) ?*Error;
pub extern fn wasmtime_component_val_delete(*Val) void;
pub extern fn wasmtime_component_resource_any_drop(*Context, *const Resource) ?*Error;
pub extern fn nb_component_allocation_limit(usize) void;
pub extern fn nb_component_allocation_peak() usize;
pub extern fn nb_component_profile([*]const u8, usize, u32, u32, u32) i32;
pub extern fn wasmtime_component_type(*const Component) ?*ComponentType;
pub extern fn wasmtime_component_type_delete(*ComponentType) void;
pub extern fn wasmtime_component_type_import_count(*const ComponentType, *const Engine) usize;
pub extern fn wasmtime_component_type_export_count(*const ComponentType, *const Engine) usize;
pub extern fn wasmtime_component_type_import_nth(
    *const ComponentType,
    *const Engine,
    usize,
    *?[*]const u8,
    *usize,
    *?*Extern,
) bool;
pub extern fn wasmtime_component_type_export_nth(
    *const ComponentType,
    *const Engine,
    usize,
    *?[*]const u8,
    *usize,
    *?*Extern,
) bool;
pub extern fn wasmtime_component_type_export_get(
    *const ComponentType,
    *const Engine,
    [*]const u8,
    usize,
    *?*Extern,
) bool;
pub extern fn wasmtime_component_extern_type(*const Extern, *Item) void;
pub extern fn wasmtime_component_extern_delete(*Extern) void;
pub extern fn wasmtime_component_item_delete(*Item) void;
pub extern fn wasmtime_component_instance_type_export_count(
    *const InstanceType,
    *const Engine,
) usize;
pub extern fn wasmtime_component_instance_type_export_nth(
    *const InstanceType,
    *const Engine,
    usize,
    *?[*]const u8,
    *usize,
    *?*Extern,
) bool;
pub extern fn wasmtime_component_instance_type_export_get(
    *const InstanceType,
    *const Engine,
    [*]const u8,
    usize,
    *?*Extern,
) bool;
pub extern fn wasmtime_component_func_type_async(*const FuncType) bool;
pub extern fn wasmtime_component_func_type_param_count(*const FuncType) usize;
pub extern fn wasmtime_component_func_type_param_nth(
    *const FuncType,
    usize,
    *?[*]const u8,
    *usize,
    *ValType,
) bool;
pub extern fn wasmtime_component_func_type_result(*const FuncType, *ValType) bool;
pub extern fn wasmtime_component_valtype_delete(*ValType) void;
pub extern fn wasmtime_component_list_type_element(*const ListType, *ValType) void;
pub extern fn wasmtime_component_record_type_field_count(*const RecordType) usize;
pub extern fn wasmtime_component_record_type_field_nth(
    *const RecordType,
    usize,
    *?[*]const u8,
    *usize,
    *ValType,
) bool;
pub extern fn wasmtime_component_variant_type_case_count(*const VariantType) usize;
pub extern fn wasmtime_component_variant_type_case_nth(
    *const VariantType,
    usize,
    *?[*]const u8,
    *usize,
    *bool,
    *ValType,
) bool;
pub extern fn wasmtime_component_option_type_ty(*const OptionType, *ValType) void;
pub extern fn wasmtime_component_result_type_ok(*const ResultType, *ValType) bool;
pub extern fn wasmtime_component_result_type_err(*const ResultType, *ValType) bool;
pub extern fn wasmtime_component_tuple_type_types_count(*const TupleType) usize;
pub extern fn wasmtime_component_tuple_type_types_nth(*const TupleType, usize, *ValType) bool;
pub extern fn wasmtime_component_enum_type_names_count(*const EnumType) usize;
pub extern fn wasmtime_component_enum_type_names_nth(
    *const EnumType, usize, *?[*]const u8, *usize,
) bool;
pub extern fn wasmtime_component_flags_type_names_count(*const FlagsType) usize;
pub extern fn wasmtime_component_flags_type_names_nth(
    *const FlagsType, usize, *?[*]const u8, *usize,
) bool;
