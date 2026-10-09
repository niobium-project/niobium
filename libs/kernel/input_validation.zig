//! Compiled WIT input contracts are enforced before root claims and before persisted reuse.
const program = @import("program");
const t = @import("types.zig");
const std = @import("std");
const wire = @import("wire.zig");

pub fn defaults(product: program.model.Product) t.Error!void {
    for (product.inputs) |input| {
        const declared = input.resolved_type orelse return error.ProgramInvalid;
        try program.wit.validateDeclaredInput(input.default, declared);
    }
}

pub fn overrides(
    arena: std.mem.Allocator,
    product: program.model.Product,
    inputs: []const t.Input,
) t.Error!void {
    for (inputs) |input| {
        const declared = program.find(program.model.Input, product.inputs, input.id) orelse
            return error.KernelInvalid;
        try program.wit.validateDeclaredInput(
            input.value,
            declared.resolved_type orelse return error.ProgramInvalid,
        );
    }
    const encoded = try wire.encode(arena, inputs);
    std.debug.assert(encoded.len >= 2);
}

pub fn persisted(product: program.model.Product, inputs: []const t.Input) t.Error!void {
    for (inputs) |input| {
        const declared = program.find(
            program.model.Input,
            product.inputs,
            input.id,
        ) orelse continue;
        try program.wit.validateDeclaredInput(
            input.value,
            declared.resolved_type orelse return error.ProgramInvalid,
        );
    }
}
