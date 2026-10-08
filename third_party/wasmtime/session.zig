//! Worker-local upstream engine integration. Never load this allocator into the journal parent.
const std = @import("std");
pub const c = @import("bindings.zig");
pub const Error = error{
    Engine,
    Guest,
    AutomaticInitialization,
    Profile,
    ResourceLimit,
    UnauthorizedImport,
};
pub const Limits = struct {
    component_bytes: usize,
    modules: u32,
    types: u32,
    depth: u32,
    memory_bytes: u32,
    memories: u32,
    table_elements: u32,
    instructions: u64,
    stack_bytes: usize,
    allocation_bytes: usize,
};
pub const Names = struct { interface: []const u8, function: []const u8 };
pub const HostFunction = struct {
    name: []const u8,
    callback: c.Callback,
    userdata: ?*anyopaque,
};

pub const Session = struct {
    engine: *c.Engine,
    store: *c.Store,
    component: *c.Component,
    linker: *c.Linker,
    instance: ?c.Instance = null,

    pub fn load(bytes: []const u8, limits: Limits) Error!Session {
        std.debug.assert(limits.instructions > 0);
        if (bytes.len > limits.component_bytes) return error.ResourceLimit;
        c.nb_component_allocation_limit(limits.allocation_bytes);
        const profile = c.nb_component_profile(
            bytes.ptr,
            bytes.len,
            limits.modules,
            limits.types,
            limits.depth,
        );
        switch (profile) {
            0 => {},
            -2 => return error.AutomaticInitialization,
            -3 => return error.ResourceLimit,
            else => return error.Profile,
        }
        const engine = try newEngine(limits);
        errdefer c.wasm_engine_delete(engine);
        const store = c.wasmtime_store_new(engine, null, null) orelse return error.Engine;
        errdefer c.wasmtime_store_delete(store);
        c.wasmtime_store_limiter(
            store,
            limits.memory_bytes,
            limits.table_elements,
            limits.modules,
            limits.modules,
            limits.memories,
        );
        const context = c.wasmtime_store_context(store);
        try checked(c.wasmtime_context_set_fuel(context, limits.instructions));
        var component: ?*c.Component = null;
        try checked(c.wasmtime_component_new(engine, bytes.ptr, bytes.len, &component));
        const loaded = component orelse return error.Engine;
        errdefer c.wasmtime_component_delete(loaded);
        const linker = c.wasmtime_component_linker_new(engine) orelse return error.Engine;
        errdefer c.wasmtime_component_linker_delete(linker);
        return .{ .engine = engine, .store = store, .component = loaded, .linker = linker };
    }

    pub fn addHost(
        self: *Session,
        names: Names,
        callback: c.Callback,
        userdata: ?*anyopaque,
    ) Error!void {
        return self.addHosts(names.interface, &.{.{
            .name = names.function,
            .callback = callback,
            .userdata = userdata,
        }});
    }

    pub fn addHosts(self: *Session, name: []const u8, functions: []const HostFunction) Error!void {
        std.debug.assert(self.instance == null);
        try validName(name);
        if (functions.len > 64) return error.ResourceLimit;
        const root = c.wasmtime_component_linker_root(self.linker) orelse return error.Engine;
        defer c.wasmtime_component_linker_instance_delete(root);
        var child: ?*c.LinkerInstance = null;
        try checked(c.wasmtime_component_linker_instance_add_instance(
            root,
            name.ptr,
            name.len,
            &child,
        ));
        const interface = child orelse return error.Engine;
        defer c.wasmtime_component_linker_instance_delete(interface);
        for (functions) |function| {
            try validName(function.name);
            try checked(c.wasmtime_component_linker_instance_add_func(
                interface,
                function.name.ptr,
                function.name.len,
                function.callback,
                function.userdata,
                null,
            ));
        }
    }

    pub fn componentType(self: *const Session) Error!*c.ComponentType {
        return c.wasmtime_component_type(self.component) orelse error.Engine;
    }

    pub fn instantiate(self: *Session, allowed_imports: []const []const u8) Error!void {
        std.debug.assert(self.instance == null);
        try self.checkImports(allowed_imports);
        var instance: c.Instance = undefined;
        try checked(c.wasmtime_component_linker_instantiate(
            self.linker,
            c.wasmtime_store_context(self.store),
            self.component,
            &instance,
        ));
        self.instance = instance;
    }

    pub fn checkImports(self: *const Session, allowed: []const []const u8) Error!void {
        if (allowed.len > 64) return error.ResourceLimit;
        for (allowed) |name| try validName(name);
        const component_type = try self.componentType();
        defer c.wasmtime_component_type_delete(component_type);
        const count = c.wasmtime_component_type_import_count(component_type, self.engine);
        if (count > 64) return error.ResourceLimit;
        for (0..count) |index| {
            var name: ?[*]const u8 = null;
            var len: usize = 0;
            var external: ?*c.Extern = null;
            if (!c.wasmtime_component_type_import_nth(
                component_type,
                self.engine,
                index,
                &name,
                &len,
                &external,
            )) return error.Engine;
            const imported_type = external orelse return error.Engine;
            defer c.wasmtime_component_extern_delete(imported_type);
            if (len > 256) return error.ResourceLimit;
            const imported = (name orelse return error.Engine)[0..len];
            for (allowed) |entry| {
                if (std.mem.eql(u8, imported, entry)) break;
            } else return error.UnauthorizedImport;
        }
    }

    pub fn deinit(self: *Session) void {
        c.wasmtime_component_linker_delete(self.linker);
        c.wasmtime_store_delete(self.store);
        c.wasmtime_component_delete(self.component);
        c.wasm_engine_delete(self.engine);
    }

    pub fn call(self: *Session, names: Names, args: []const c.Val, out: []c.Val) Error!void {
        std.debug.assert(names.function.len != 0);
        if (names.interface.len > 0) try validName(names.interface);
        try validName(names.function);
        const instance = &(self.instance orelse return error.Engine);
        if (out.len > 1 or args.len > 64) return error.ResourceLimit;
        // v49.0.2 drops existing C result slots despite its header's initial-value wording.
        // Callers must release any previous results before reusing these output slots.
        for (out) |*value| value.* = .{ .kind = c.bool_kind, .of = .{ .boolean = false } };
        const context = c.wasmtime_store_context(self.store);
        const interface = if (names.interface.len == 0) null else c.wasmtime_component_instance_get_export_index(
            instance,
            context,
            null,
            names.interface.ptr,
            names.interface.len,
        ) orelse return error.Guest;
        if (names.interface.len > 0 and interface == null) return error.Guest;
        defer if (interface) |index| c.wasmtime_component_export_index_delete(index);
        const index = c.wasmtime_component_instance_get_export_index(
            instance,
            context,
            interface,
            names.function.ptr,
            names.function.len,
        ) orelse return error.Guest;
        defer c.wasmtime_component_export_index_delete(index);
        var func: c.Func = undefined;
        if (!c.wasmtime_component_instance_get_func(instance, context, index, &func)) {
            return error.Guest;
        }
        try checked(c.wasmtime_component_func_call(
            &func,
            context,
            args.ptr,
            args.len,
            out.ptr,
            out.len,
        ));
    }
};

fn newEngine(limits: Limits) Error!*c.Engine {
    const config = c.wasm_config_new() orelse return error.Engine;
    checked(c.wasmtime_config_target_set(config, "pulley64")) catch |err| {
        c.wasm_config_delete(config);
        return err;
    };
    c.wasmtime_config_consume_fuel_set(config, true);
    c.wasmtime_config_max_wasm_stack_set(config, limits.stack_bytes);
    c.wasmtime_config_memory_reservation_set(config, limits.memory_bytes);
    c.wasmtime_config_memory_reservation_for_growth_set(config, 0);
    c.wasmtime_config_signals_based_traps_set(config, false);
    return c.wasm_engine_new_with_config(config) orelse error.Engine;
}

fn validName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > 256) return error.ResourceLimit;
    if (!std.unicode.utf8ValidateSlice(name)) return error.Profile;
}

pub fn checked(maybe_error: ?*c.Error) Error!void {
    if (maybe_error) |err| {
        defer c.wasmtime_error_delete(err);
        var message: c.Bytes = undefined;
        c.wasmtime_error_message(err, &message);
        defer c.wasm_byte_vec_delete(&message);
        if (message.data) |data| std.log.err("Wasmtime: {s}", .{data[0..@min(message.size, 2048)]});
        return error.Guest;
    }
}
