//! Exact source locks and separate canonical content identities.

const std = @import("std");
const contracts = @import("contracts");
const content = @import("content");
const image = @import("image");
const program = @import("program");
const lock = @import("lock.zig");
const types = @import("pipeline_types.zig");

pub fn validate(
    arena: std.mem.Allocator,
    io: std.Io,
    request: types.Request,
    diagnostic: *?types.Diagnostic,
) types.Error!void {
    try lock.validate(request.lock);
    if (request.inputs.len != request.lock.inputs.len) return error.CompileInputMissing;
    for (request.inputs, 0..) |input, index| {
        for (request.inputs[0..index]) |prior| {
            if (std.mem.eql(u8, prior.id, input.id)) return error.ProgramDuplicate;
        }
        const expected = program.find(lock.Input, request.lock.inputs, input.id) orelse
            return error.CompileInputMissing;
        verify(io, request, expected, input.source) catch |err| {
            types.report(diagnostic, request, .lock, .identity_mismatch, .input, input.id, err);
            return err;
        };
    }
    for (request.product.libraries) |library| {
        const expected = program.find(lock.Input, request.lock.inputs, library.id) orelse
            return error.CompileInputMissing;
        if (expected.kind != .library or expected.bytes != library.bytes or
            !std.mem.eql(u8, expected.sha256, library.sha256)) return error.LockMismatch;
    }
    for (request.product.containers) |container| {
        const expected = program.find(lock.Input, request.lock.inputs, container.id) orelse
            return error.CompileInputMissing;
        if (expected.kind != .content) return error.LockMismatch;
    }
    try runtime(arena, io, request);
}

pub fn verify(
    io: std.Io,
    request: types.Request,
    expected: lock.Input,
    source: content.Source,
) types.Error!void {
    if (source.size() != expected.bytes) return error.LockMismatch;
    const wanted = contracts.ids.parseHex32(expected.sha256) orelse return error.ProgramDigest;
    const actual = try hash(io, request, source);
    if (!std.mem.eql(u8, &wanted, &actual)) return error.LockMismatch;
}

pub fn hash(
    io: std.Io,
    request: types.Request,
    source: content.Source,
) types.Error!contracts.Digest {
    if (source.size() > contracts.limits.default.native_image_bytes) return error.ProgramLimit;
    var hasher: std.crypto.hash.sha2.Sha256 = .init(.{});
    var bytes: [64 << 10]u8 = undefined; // SAFETY: read fills every hashed slice.
    var offset: u64 = 0;
    while (offset < source.size()) {
        try types.canceled(request);
        const count = std.math.cast(usize, @min(bytes.len, source.size() - offset)) orelse
            return error.ProgramLimit;
        try source.read(io, offset, bytes[0..count]);
        hasher.update(bytes[0..count]);
        offset += count;
    }
    return hasher.finalResult();
}

fn runtime(arena: std.mem.Allocator, io: std.Io, request: types.Request) types.Error!void {
    const expected = program.find(lock.Input, request.lock.inputs, request.runtime_id) orelse
        return error.CompileInputMissing;
    if (expected.kind != .runtime or expected.target != request.product.target)
        return error.LockMismatch;
    try program.profile.validate(request.runtime_profile);
    if (!std.mem.eql(u8, request.runtime_profile.id, request.product.profile.id) or
        request.runtime_profile.primitives.len != request.product.profile.primitives.len)
    {
        return error.ProfileMismatch;
    }
    try program.profile.require(
        request.runtime_profile,
        request.product.target,
        request.product.profile.primitives,
    );
    const input = try types.input(request, request.runtime_id);
    const layout = try image.native.inspect(arena, io, input.source, .{});
    const target: program.profile.Target = switch (layout.format) {
        .macho => if (layout.cpu == .aarch64) .@"aarch64-macos" else return error.ProfileMismatch,
        .pe => if (layout.cpu == .x86_64) .@"x86_64-windows" else return error.ProfileMismatch,
        .elf => if (layout.cpu == .x86_64) .@"x86_64-linux" else return error.ProfileMismatch,
    };
    if (target != request.product.target) return error.ProfileMismatch;
    var slot: [image.descriptor.size]u8 = undefined; // SAFETY: source read initializes the slot.
    try input.source.read(io, layout.slot.offset, &slot);
    try image.descriptor.checkTemplate(&slot);
}

pub fn canonical(
    arena: std.mem.Allocator,
    io: std.Io,
    source: content.Source,
    output: *std.Io.Writer,
    expected: content.ContainerRef,
) types.Error!void {
    const tree = try content.parseTar(arena, io, source, .{});
    const actual = try content.writeTar(arena, io, tree, output, .{});
    if (actual.bytes != expected.bytes or actual.format != expected.format or
        !std.mem.eql(u8, &actual.sha256, &expected.sha256)) return error.LockMismatch;
}
