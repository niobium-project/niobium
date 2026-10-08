//! Bind fixed Component exports using upstream-reflected WIT descriptors.

const std = @import("std");
const program = @import("program");
const contracts = @import("contracts");
const types = @import("pipeline_types.zig");
const wit = program.wit;
const model = program.model;

pub fn bind(
    arena: std.mem.Allocator,
    io: std.Io,
    request: types.Request,
    diagnostic: *?types.Diagnostic,
) types.Error!model.Product {
    std.debug.assert(request.product.calls.len <= contracts.limits.default.program_items);
    const inputs = try arena.dupe(model.Input, request.product.inputs);
    for (inputs) |input| if (input.resolved_type != null) {
        types.report(
            diagnostic,
            request,
            .binding,
            .type_mismatch,
            .@"author-input",
            input.id,
            error.AuthoringResolvedType,
        );
        return error.AuthoringResolvedType;
    };
    var inspected: std.ArrayList(types.LibraryContract) = .empty;
    for (request.product.libraries) |library| {
        try types.canceled(request);
        const inspector = request.inspector orelse return error.ContractUnavailable;
        const inspection = inspector.inspect(
            inspector.context,
            arena,
            io,
            library,
            try types.input(request, library.id),
            try types.tool(request, inspector.tool_id),
        ) catch |err| {
            types.report(
                diagnostic,
                request,
                .capability,
                .capability_mismatch,
                .library,
                library.id,
                err,
            );
            return err;
        };
        imports(inspection) catch |err| {
            types.report(
                diagnostic,
                request,
                .capability,
                .capability_mismatch,
                .library,
                library.id,
                err,
            );
            return err;
        };
        try inspected.append(arena, .{ .id = library.id, .inspection = inspection });
    }
    for (request.product.observations) |observation| {
        const observed = try observationType(request, observation);
        if (observed.params.len != observation.arguments.len) return error.WitTypeMismatch;
        for (observed.params, observation.arguments) |parameter, argument| {
            try wit.validateValue(argument, parameter.ty);
        }
    }
    for (try model.order(arena, request.product)) |index| {
        const call = request.product.calls[index];
        checkCall(request, inspected.items, inputs, call) catch |err| {
            types.report(diagnostic, request, .binding, .type_mismatch, .call, call.id, err);
            return err;
        };
    }
    try inferUnused(arena, request, inputs, diagnostic);
    var result = request.product;
    result.inputs = inputs;
    return result;
}

fn inferUnused(
    arena: std.mem.Allocator,
    request: types.Request,
    inputs: []model.Input,
    diagnostic: *?types.Diagnostic,
) types.Error!void {
    for (inputs) |*input| {
        if (input.resolved_type != null) continue;
        input.resolved_type = try wit.inferInputType(arena, input.default);
        if (input.resolved_type == null) {
            types.report(
                diagnostic,
                request,
                .binding,
                .type_mismatch,
                .@"author-input",
                input.id,
                error.InputTypeAmbiguous,
            );
            return error.InputTypeAmbiguous;
        }
    }
}

fn imports(inspection: wit.Inspection) types.Error!void {
    if (inspection.imports.len > contracts.limits.default.component_types) return error.WitLimit;
    for (inspection.imports) |item| {
        // Component profile 1 exposes facts as prebound observations, never guest call imports.
        if (!try wit.isTypeOnlyImport(item)) return error.ContractRejected;
    }
}

fn signature(
    items: []const types.LibraryContract,
    library: []const u8,
    interface: []const u8,
    function: []const u8,
) types.Error!wit.FunctionType {
    const found = program.find(
        types.LibraryContract,
        items,
        library,
    ) orelse return error.ProgramReference;
    const result = try wit.findFunction(found.inspection.exports, interface, function);
    try durableFunction(result);
    return result;
}

fn durableFunction(function: wit.FunctionType) types.Error!void {
    if (function.asynchronous) return error.ContractRejected;
    for (function.params) |parameter| try wit.validateInputType(parameter.ty);
    if (function.result) |result| try wit.validateInputType(result.*);
}

fn observationType(
    request: types.Request,
    observation: model.Observation,
) types.Error!wit.FunctionType {
    for (request.hosts) |host| {
        if (host.primitive.version != observation.primitive.version or
            !std.mem.eql(u8, host.primitive.id, observation.primitive.id)) continue;
        const result = try wit.findFunction(host.functions, "", observation.function);
        try durableFunction(result);
        return result;
    }
    return error.ContractUnavailable;
}

fn checkCall(
    request: types.Request,
    libraries: []const types.LibraryContract,
    inputs: []model.Input,
    call: model.Call,
) types.Error!void {
    const function = try signature(libraries, call.library, call.interface, call.function);
    if (function.params.len != call.arguments.len) return error.WitTypeMismatch;
    const state: ?wit.Type = if (call.result_role == .plan) try plan(function) else null;
    var checker: Checker = .{
        .request = request,
        .libraries = libraries,
        .inputs = inputs,
        .state = state,
    };
    for (call.arguments, function.params) |argument, parameter| {
        try checker.binding(argument, parameter.ty, 0);
    }
    for (call.migrations) |migration| {
        const converter = try signature(
            libraries,
            migration.library,
            migration.interface,
            migration.function,
        );
        if (converter.params.len != 1) return error.WitTypeMismatch;
        const output = unwrap((converter.result orelse return error.WitTypeMismatch).*) catch
            return error.WitTypeMismatch;
        const target = state orelse return error.WitTypeMismatch;
        try wit.compatible(output, target.option.*);
    }
}

const Checker = struct {
    request: types.Request,
    libraries: []const types.LibraryContract,
    inputs: []model.Input,
    state: ?wit.Type,
    nodes: u32 = 0,

    fn binding(
        self: *Checker,
        argument: model.Binding,
        expected: wit.Type,
        depth: u8,
    ) types.Error!void {
        if (depth >= contracts.limits.default.component_depth or
            self.nodes >= contracts.limits.default.component_types) return error.WitLimit;
        self.nodes += 1;
        switch (argument) {
            .literal => |value| try wit.validateValue(value, expected),
            .input => |id| try self.input(id, expected),
            .node_result => |projection| {
                const node = program.find(
                    model.Call,
                    self.request.product.calls,
                    projection.id,
                ) orelse return error.ProgramReference;
                const prior = try signature(
                    self.libraries,
                    node.library,
                    node.interface,
                    node.function,
                );
                const output = (prior.result orelse return error.WitTypeMismatch).*;
                const bound = if (node.result_role == .plan) try unwrap(output) else output;
                try wit.compatible(try wit.selectType(bound, projection.fields), expected);
            },
            .observation => |projection| {
                const observation = program.find(
                    model.Observation,
                    self.request.product.observations,
                    projection.id,
                ) orelse return error.ProgramReference;
                const observed = try observationType(self.request, observation);
                const output = (observed.result orelse return error.WitTypeMismatch).*;
                try wit.compatible(try wit.selectType(output, projection.fields), expected);
            },
            .previous_state => try wit.compatible(
                self.state orelse return error.WitTypeMismatch,
                expected,
            ),
            .record => |items| try self.record(items, expected, depth + 1),
            .list => |items| {
                if (expected != .list) return error.WitTypeMismatch;
                for (items) |item| try self.binding(item, expected.list.*, depth + 1);
            },
            .tuple => |items| {
                if (expected != .tuple or expected.tuple.len != items.len)
                    return error.WitTypeMismatch;
                for (items, expected.tuple) |item, ty| try self.binding(item, ty, depth + 1);
            },
            .some => |item| {
                if (expected != .option) return error.WitTypeMismatch;
                try self.binding(item.*, expected.option.*, depth + 1);
            },
        }
    }

    fn input(self: *Checker, id: []const u8, expected: wit.Type) types.Error!void {
        for (self.inputs) |*item| {
            if (!std.mem.eql(u8, item.id, id)) continue;
            if (item.resolved_type) |previous| try wit.compatible(previous, expected);
            try wit.validateDeclaredInput(item.default, expected);
            if (item.resolved_type == null) item.resolved_type = expected;
            return;
        }
        return error.ProgramReference;
    }

    fn record(
        self: *Checker,
        items: []const model.BindingField,
        expected: wit.Type,
        depth: u8,
    ) types.Error!void {
        if (expected != .record or expected.record.len != items.len) return error.WitTypeMismatch;
        for (items) |item| {
            const ty = try wit.selectType(expected, &.{item.name});
            try self.binding(item.binding, ty, depth);
        }
    }
};

fn unwrap(value: wit.Type) types.Error!wit.Type {
    return if (value == .result) (value.result.ok orelse return error.WitTypeMismatch).* else value;
}

/// A plan's private state retains its concrete WIT type; no universal state DSL is introduced.
pub fn plan(function: wit.FunctionType) types.Error!wit.Type {
    const result = try unwrap((function.result orelse return error.WitTypeMismatch).*);
    const containers = try wit.selectType(result, &.{"containers"});
    if (containers != .list) return error.WitTypeMismatch;
    const proposal = containers.list.*;
    try fields(proposal, 6);
    for ([_][]const u8{ "root", "grant", "prefix" }) |name| {
        try wit.compatible(try wit.selectType(proposal, &.{name}), .text);
    }
    const container = try wit.selectType(proposal, &.{"container"});
    if (container != .variant or container.variant.len != 2) return error.WitTypeMismatch;
    const reference = try caseType(container, "reference");
    try fields(reference, 3);
    try wit.compatible(try wit.selectType(reference, &.{"bytes"}), .uint64);
    const byte: wit.Type = .uint8;
    try wit.compatible(try wit.selectType(reference, &.{"sha256"}), .{ .list = &byte });
    try wit.compatible(try wit.selectType(reference, &.{"format"}), .{
        .enumeration = &.{"posix-pax-v1"},
    });
    const generated = try caseType(container, "generated");
    if (generated != .list) return error.WitTypeMismatch;
    const entry = generated.list.*;
    try fields(entry, 3);
    try wit.compatible(try wit.selectType(entry, &.{"path"}), .text);
    try wit.compatible(try wit.selectType(entry, &.{"mode"}), .uint16);
    const kind = try wit.selectType(entry, &.{"kind"});
    if (kind != .variant or kind.variant.len != 3) return error.WitTypeMismatch;
    try wit.compatible(try caseType(kind, "file"), .{ .list = &byte });
    try wit.compatible(try caseType(kind, "symlink"), .text);
    const directory = for (kind.variant) |item| {
        if (std.mem.eql(u8, item.name, "directory")) break item;
    } else return error.WitTypeMismatch;
    if (directory.payload != null) return error.WitTypeMismatch;
    try accessPolicy(try wit.selectType(proposal, &.{"file-access"}));
    try accessPolicy(try wit.selectType(proposal, &.{"directory-access"}));
    const state = try wit.selectType(result, &.{"state"});
    if (state != .option) return error.WitTypeMismatch;
    try wit.compatible(state, state);
    return state;
}

fn caseType(value: wit.Type, name: []const u8) types.Error!wit.Type {
    if (value != .variant) return error.WitTypeMismatch;
    for (value.variant) |item| {
        if (std.mem.eql(u8, item.name, name)) return (item.payload orelse
            return error.WitTypeMismatch).*;
    }
    return error.WitTypeMismatch;
}

fn accessPolicy(value: wit.Type) types.Error!void {
    try fields(value, 4);
    try wit.compatible(try wit.selectType(value, &.{"schema"}), .uint32);
    try wit.compatible(try wit.selectType(value, &.{"kind"}), .{
        .enumeration = &.{ "file", "directory" },
    });
    for ([_][]const u8{ "owner", "everyone" }) |subject| {
        const rights = try wit.selectType(value, &.{subject});
        try fields(rights, 3);
        for ([_][]const u8{ "read", "write", "execute" }) |right| {
            try wit.compatible(try wit.selectType(rights, &.{right}), .boolean);
        }
    }
}

fn fields(value: wit.Type, count: usize) types.Error!void {
    if (value != .record or value.record.len != count) return error.WitTypeMismatch;
}
