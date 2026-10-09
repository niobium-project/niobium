//! Version-two compiled product graph. This is compiler output, never author expressions.

const std = @import("std");
const contracts = @import("contracts");
const content = @import("content");
const access = @import("access_policy");
const program = @import("root.zig");
pub const checking = @import("model_validate.zig");
pub const wire_depth = contracts.limits.default.component_depth * 4 + 16;

pub const Error = program.Error || program.profile.Error || program.value.Error ||
    program.wit.Error || content.Error || access.Error || error{ ProgramCycle, ProgramAuthority };
pub const Input = struct {
    id: []const u8,
    default: program.value.Value,
    /// Compiler-owned complete WIT type. Author model inputs leave this null.
    resolved_type: ?program.wit.Type = null,
};
pub const Library = struct {
    id: []const u8,
    member: []const u8,
    sha256: []const u8,
    bytes: u64,
    requires: []const program.profile.Requirement = &.{},
};
pub const Container = struct {
    id: []const u8,
    member: []const u8,
    reference: content.ContainerRef,
};
pub const Root = struct { id: []const u8, scope: contracts.Scope = .user };
pub const Grant = struct {
    id: []const u8,
    root: []const u8,
    primitive: program.profile.Requirement,
    prefix: []const u8 = "",
    max_entries: u32 = contracts.limits.default.files_per_artifact,
    max_bytes: u64 = contracts.limits.default.expanded_bytes,
    file_access: access.Policy = access.private(.file),
    directory_access: access.Policy = access.private(.directory),
};
pub const Projection = struct { id: []const u8, fields: []const []const u8 = &.{} };
pub const BindingField = struct { name: []const u8, binding: Binding };
pub const Binding = union(enum) {
    literal: program.value.Value,
    input: []const u8,
    node_result: Projection,
    observation: Projection,
    previous_state: void,
    record: []const BindingField,
    list: []const Binding,
    tuple: []const Binding,
    some: *const Binding,
};
pub const Observation = struct {
    id: []const u8,
    primitive: program.profile.Requirement,
    function: []const u8,
    arguments: []const program.value.Value = &.{},
    grant: ?[]const u8 = null,
};
pub const Migration = struct {
    id: []const u8,
    from: u32,
    to: u32,
    library: []const u8,
    interface: []const u8,
    function: []const u8,
    implementation_sha256: []const u8,
};
pub const Call = struct {
    id: []const u8,
    library: []const u8,
    interface: []const u8,
    function: []const u8,
    arguments: []const Binding = &.{},
    grants: []const []const u8 = &.{},
    after: []const []const u8 = &.{},
    state_version: u32 = 1,
    migrations: []const Migration = &.{},
    result_role: enum { value, plan } = .value,
};
pub const Product = struct {
    schema: u32 = 2,
    runtime_abi: u32 = 2,
    id: []const u8,
    release_sequence: u64,
    model_version: u32 = 1,
    target: program.profile.Target,
    profile: program.profile.Profile,
    inputs: []const Input = &.{},
    libraries: []const Library = &.{},
    containers: []const Container = &.{},
    roots: []const Root = &.{},
    state_root: []const u8 = "",
    grants: []const Grant = &.{},
    observations: []const Observation = &.{},
    calls: []const Call = &.{},
    upgrades: []const program.Migration = &.{},
};

pub fn validate(product: Product) Error!void {
    try checking.validate(product, .{});
}

pub fn decode(arena: std.mem.Allocator, bytes: []const u8) Error!Product {
    const result = try contracts.json.decode(Product, arena, bytes, .{
        .max_bytes = contracts.limits.default.program_bytes,
        .max_schema = 2,
        .limits = .{ .json_depth = wire_depth },
    });
    try validate(result);
    return result;
}

pub fn encode(arena: std.mem.Allocator, product: Product) Error![]const u8 {
    const normalized = try normalize(arena, product);
    const storage = try arena.alloc(u8, contracts.limits.default.program_bytes);
    var writer: std.Io.Writer = .fixed(storage);
    std.json.Stringify.value(normalized, .{}, &writer) catch return error.ProgramLimit;
    const bytes = storage[0..writer.end];
    const checked = try decode(arena, bytes);
    std.debug.assert(checked.schema == 2);
    return bytes;
}

pub fn normalize(arena: std.mem.Allocator, product: Product) Error!Product {
    try validate(product);
    var result = product;
    inline for (.{
        "inputs", "libraries", "containers", "roots", "grants", "observations", "calls", "upgrades",
    }) |field| {
        const T = std.meta.Child(@TypeOf(@field(result, field)));
        @field(result, field) = try sorted(T, arena, @field(product, field));
    }
    result.profile.primitives = try sorted(
        program.profile.Requirement,
        arena,
        product.profile.primitives,
    );
    const libraries = try arena.dupe(Library, result.libraries);
    for (libraries) |*library| {
        library.requires = try sorted(program.profile.Requirement, arena, library.requires);
    }
    result.libraries = libraries;
    const normalizer: @import("model_normalize.zig").Normalizer = .{ .arena = arena };
    const inputs = try arena.dupe(Input, result.inputs);
    for (inputs) |*input| input.default = try normalizer.value(input.default, 0);
    result.inputs = inputs;
    const observations = try arena.dupe(Observation, result.observations);
    for (observations) |*observation| {
        const arguments = try arena.dupe(program.value.Value, observation.arguments);
        for (arguments) |*argument| argument.* = try normalizer.value(argument.*, 0);
        observation.arguments = arguments;
    }
    result.observations = observations;
    const calls = try arena.dupe(Call, result.calls);
    for (calls) |*call| {
        call.grants = try sortedIds(arena, call.grants);
        call.after = try sortedIds(arena, call.after);
        call.migrations = try sorted(Migration, arena, call.migrations);
        const arguments = try arena.dupe(Binding, call.arguments);
        for (arguments) |*argument| argument.* = try normalizer.binding(argument.*, 0);
        call.arguments = arguments;
    }
    result.calls = calls;
    return result;
}

pub fn order(arena: std.mem.Allocator, product: Product) Error![]const usize {
    try validate(product);
    return checking.order(arena, product.calls);
}

fn sorted(comptime T: type, arena: std.mem.Allocator, values: []const T) Error![]T {
    const result = try arena.dupe(T, values);
    std.mem.sort(T, result, {}, struct {
        fn less(_: void, a: T, b: T) bool {
            return std.mem.lessThan(u8, a.id, b.id);
        }
    }.less);
    return result;
}

fn sortedIds(arena: std.mem.Allocator, ids: []const []const u8) Error![]const []const u8 {
    const result = try arena.dupe([]const u8, ids);
    std.mem.sort([]const u8, result, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
    return result;
}

test {
    _ = @import("model_test.zig");
}
