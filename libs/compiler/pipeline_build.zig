//! Capture fixed inputs and atomically publish a finalized native product.

const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const content = @import("content");
const image = @import("image");
const lock = @import("lock.zig");
const types = @import("pipeline_types.zig");
const sources = @import("pipeline_sources.zig");

pub fn build(
    arena: std.mem.Allocator,
    io: std.Io,
    request: types.Request,
    output: types.Output,
    diagnostic: *?types.Diagnostic,
) types.Error!types.Built {
    diagnostic.* = null;
    try program.model.validate(request.product);
    try lock.validate(request.lock);
    try types.canceled(request);
    try program.validation.path(output.name);
    if (std.mem.findScalar(u8, output.name, '/') != null or
        std.mem.findScalar(u8, output.name, '\\') != null) return error.ProgramPath;
    var work = try Workspace.init(arena, io, output.dir, request.cancel);
    defer work.deinit();
    var captured = request;
    captured.inputs = try work.capture(request);
    const entries = try work.entries(captured);
    const compiled = try @import("pipeline_compile.zig").prepare(
        arena,
        io,
        captured,
        diagnostic,
        true,
    );
    const payload_file = try work.create("payload.tar");
    var buffer: [64 << 10]u8 = undefined; // SAFETY: writer owns the scratch buffer.
    var writer = payload_file.writer(io, &buffer);
    const payload_ref = try content.writeTar(
        arena,
        io,
        .{ .entries = entries },
        &writer.interface,
        .{},
    );
    writer.interface.flush() catch return error.CompileIo;
    payload_file.sync(io) catch return error.CompileIo;
    const runtime = try types.input(captured, request.runtime_id);
    const assembly = try assemble(io, arena, runtime.source, compiled.bytes, payload_file, &work);
    const locked_runtime = program.find(lock.Input, request.lock.inputs, request.runtime_id) orelse
        return error.CompileInputMissing;
    const expected = contracts.ids.parseHex32(locked_runtime.sha256) orelse
        return error.ProgramDigest;
    if (!std.mem.eql(
        u8,
        &expected,
        &assembly.descriptor.template_sha256,
    )) return error.LockMismatch;
    try finish(arena, io, captured, output, &work, assembly, diagnostic);
    const result = try verifyFinal(arena, io, captured, &work, assembly, payload_ref, compiled);
    try types.canceled(request);
    work.dir.rename("setup", output.dir, output.name, io) catch return error.CompileIo;
    return result;
}

fn assemble(
    io: std.Io,
    arena: std.mem.Allocator,
    runtime: content.Source,
    bytes: []const u8,
    payload: std.Io.File,
    work: *Workspace,
) types.Error!image.Assembly {
    const file = work.dir.createFile(io, "setup", .{
        .exclusive = true,
        .read = true,
        .permissions = privateFile(),
    }) catch return error.CompileIo;
    defer file.close(io);
    const source = try fileSource(io, payload, work.cancel);
    const assembled = try image.assemble(arena, io, runtime, .bytes(bytes), .{
        .source = source,
        .length = source.size(),
    }, file, .{});
    file.sync(io) catch return error.CompileIo;
    return assembled;
}

fn finish(
    arena: std.mem.Allocator,
    io: std.Io,
    request: types.Request,
    output: types.Output,
    work: *Workspace,
    assembly: image.Assembly,
    diagnostic: *?types.Diagnostic,
) types.Error!void {
    if (output.finalizer == null and assembly.requires_signing) {
        types.report(
            diagnostic,
            request,
            .signing,
            .signing_required,
            .product,
            request.product.id,
            error.SigningRequired,
        );
        return error.SigningRequired;
    }
    try types.canceled(request);
    if (output.finalizer) |finalizer| {
        const path = try work.path("setup");
        finalizer.finalize(
            finalizer.context,
            arena,
            io,
            path,
            assembly.format,
            try types.tool(request, finalizer.tool_id),
        ) catch |err| {
            types.report(
                diagnostic,
                request,
                .signing,
                .io_failure,
                .product,
                request.product.id,
                err,
            );
            return err;
        };
    }
}

fn verifyFinal(
    arena: std.mem.Allocator,
    io: std.Io,
    request: types.Request,
    work: *Workspace,
    assembly: image.Assembly,
    payload_ref: content.ContainerRef,
    compiled: types.Compiled,
) types.Error!types.Built {
    const final = work.dir.openFile(io, "setup", .{ .mode = .read_write }) catch
        return error.CompileIo;
    defer final.close(io);
    const source = try fileSource(io, final, request.cancel);
    const descriptor = try image.verify(arena, io, source, .{});
    if (!std.meta.eql(descriptor, assembly.descriptor)) return error.ImageDigest;
    const runtime = try types.input(request, request.runtime_id);
    try preserveCode(arena, io, runtime.source, source);
    if (std.Io.File.Permissions.has_executable_bit) {
        final.setPermissions(io, .fromMode(0o755)) catch return error.CompileIo;
    }
    final.sync(io) catch return error.CompileIo;
    return .{
        .program_sha256 = compiled.sha256,
        .payload = payload_ref,
        .setup_sha256 = try sources.hash(io, request, source),
        .bytes = source.size(),
        .cache_hit = compiled.cache_hit,
    };
}

fn preserveCode(
    arena: std.mem.Allocator,
    io: std.Io,
    original: content.Source,
    final: content.Source,
) types.Error!void {
    const before = try image.native.inspect(arena, io, original, .{});
    const after = try image.native.inspect(arena, io, final, .{});
    if (before.format != after.format or before.cpu != after.cpu or
        before.code.len != after.code.len)
    {
        return error.ImageInvalid;
    }
    for (before.code, after.code) |left, right| {
        if (!std.meta.eql(left, right)) return error.ImageInvalid;
        var scratch: [4096]u8 = undefined; // SAFETY: discard sink uses initialized written slices.
        var sink: std.Io.Writer.Discarding = .init(&scratch);
        const a = try content.freeze(io, .{
            .source = original,
            .offset = left.offset,
            .length = left.length,
        }, &sink.writer, .{});
        const b = try content.freeze(io, .{
            .source = final,
            .offset = right.offset,
            .length = right.length,
        }, &sink.writer, .{});
        if (!std.mem.eql(u8, &a.sha256, &b.sha256)) return error.ImageDigest;
    }
}

const Workspace = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    dir: std.Io.Dir,
    name: []const u8,
    cancel: ?*const std.atomic.Value(bool),
    files: std.ArrayList(std.Io.File) = .empty,

    fn init(
        arena: std.mem.Allocator,
        io: std.Io,
        parent: std.Io.Dir,
        cancel: ?*const std.atomic.Value(bool),
    ) types.Error!Workspace {
        var random: [16]u8 = undefined; // SAFETY: random initializes the staging identity.
        io.random(&random);
        const name = try arena.print(".niobium-build-{s}", .{std.fmt.bytesToHex(random, .lower)});
        const permissions: std.Io.File.Permissions = if (std.Io.File.Permissions.has_executable_bit)
            .fromMode(0o700)
        else
            .default_dir;
        parent.createDir(io, name, permissions) catch return error.CompileIo;
        const dir = parent.openDir(io, name, .{}) catch return error.CompileIo;
        return .{
            .arena = arena,
            .io = io,
            .parent = parent,
            .dir = dir,
            .name = name,
            .cancel = cancel,
        };
    }

    fn deinit(self: *Workspace) void {
        for (self.files.items) |file| file.close(self.io);
        self.dir.close(self.io);
        self.parent.deleteTree(self.io, self.name) catch |err|
            std.log.warn("compiler staging cleanup: {s}", .{@errorName(err)});
    }

    fn create(self: *Workspace, name: []const u8) types.Error!std.Io.File {
        const file = self.dir.createFile(self.io, name, .{
            .exclusive = true,
            .read = true,
            .permissions = privateFile(),
        }) catch return error.CompileIo;
        errdefer file.close(self.io);
        try self.files.append(self.arena, file);
        return file;
    }

    fn path(self: *Workspace, name: []const u8) types.Error![]const u8 {
        return self.dir.realPathFileAlloc(self.io, name, self.arena) catch error.CompileIo;
    }

    fn capture(self: *Workspace, request: types.Request) types.Error![]const types.Input {
        if (request.inputs.len != request.lock.inputs.len) return error.CompileInputMissing;
        const inputs = try self.arena.alloc(types.Input, request.inputs.len);
        for (request.lock.inputs, 0..) |expected, index| {
            const provided = try types.input(request, expected.id);
            if (provided.source.size() != expected.bytes) return error.LockMismatch;
            const suffix = if (expected.kind == .tool and
                @import("builtin").target.os.tag == .windows) ".exe" else "";
            const name = try self.arena.print("input-{d}{s}", .{ index, suffix });
            const file = try self.create(name);
            const actual = try captureFile(self.io, request, provided.source, file);
            const reference = contracts.ids.parseHex32(expected.sha256) orelse
                return error.ProgramDigest;
            if (!std.mem.eql(u8, &actual, &reference)) return error.LockMismatch;
            if (expected.kind == .tool and std.Io.File.Permissions.has_executable_bit) {
                file.setPermissions(self.io, .fromMode(0o700)) catch return error.CompileIo;
            }
            file.sync(self.io) catch return error.CompileIo;
            const captured = if (expected.kind == .tool) try self.sealTool(name, file) else file;
            inputs[index] = .{
                .id = expected.id,
                .source = try fileSource(self.io, captured, request.cancel),
                .path = try self.path(name),
            };
        }
        return inputs;
    }

    fn sealTool(self: *Workspace, name: []const u8, writable: std.Io.File) types.Error!std.Io.File {
        std.debug.assert(self.files.items.len > 0);
        const readable = self.dir.openFile(self.io, name, .{}) catch return error.CompileIo;
        // Linux rejects exec while any writable descriptor refers to the executable inode.
        self.files.items[self.files.items.len - 1] = readable;
        writable.close(self.io);
        return readable;
    }

    fn entries(self: *Workspace, request: types.Request) types.Error![]const content.Entry {
        var result: std.ArrayList(content.Entry) = .empty;
        for (request.product.libraries) |library| {
            const input = try types.input(request, library.id);
            try result.append(
                self.arena,
                .{
                    .path = library.member,
                    .body = .{ .source = input.source, .length = input.source.size() },
                },
            );
        }
        for (request.product.containers, 0..) |container, index| {
            try types.canceled(request);
            const input = try types.input(request, container.id);
            const name = try self.arena.print("container-{d}.tar", .{index});
            const file = try self.create(name);
            var buffer: [64 << 10]u8 = undefined; // SAFETY: file writer owns this scratch space.
            var writer = file.writer(self.io, &buffer);
            try sources.canonical(
                self.arena,
                self.io,
                input.source,
                &writer.interface,
                container.reference,
            );
            writer.interface.flush() catch return error.CompileIo;
            file.sync(self.io) catch return error.CompileIo;
            try result.append(
                self.arena,
                .{
                    .path = container.member,
                    .body = .{
                        .source = try fileSource(self.io, file, request.cancel),
                        .length = container.reference.bytes,
                    },
                },
            );
        }
        return result.items;
    }
};

fn captureFile(
    io: std.Io,
    request: types.Request,
    source: content.Source,
    file: std.Io.File,
) types.Error!contracts.Digest {
    var buffer: [64 << 10]u8 = undefined; // SAFETY: read initializes every copied slice.
    var hash: std.crypto.hash.sha2.Sha256 = .init(.{});
    var offset: u64 = 0;
    while (offset < source.size()) {
        try types.canceled(request);
        const count = std.math.cast(usize, @min(buffer.len, source.size() - offset)) orelse
            return error.ProgramLimit;
        try source.read(io, offset, buffer[0..count]);
        file.writeStreamingAll(io, buffer[0..count]) catch return error.CompileIo;
        hash.update(buffer[0..count]);
        offset += count;
    }
    return hash.finalResult();
}

fn fileSource(
    io: std.Io,
    file: std.Io.File,
    cancel: ?*const std.atomic.Value(bool),
) types.Error!content.Source {
    const stat = file.stat(io) catch return error.CompileIo;
    return .{ .file = .{ .handle = file, .length = stat.size, .cancel = cancel } };
}

fn privateFile() std.Io.File.Permissions {
    return if (std.Io.File.Permissions.has_executable_bit) .fromMode(0o600) else .default_file;
}
