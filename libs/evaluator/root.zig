//! Execute a fixed typed capability DAG and normalize its proposals before kernel mutation.
const std = @import("std");
const program = @import("program");
const contracts = @import("contracts");
const content = @import("content");
const kernel = @import("kernel");
const client = @import("component_client");
const primitives = @import("host_primitives");
pub const bindings = @import("bindings.zig");
pub const values = @import("values.zig");
pub const executable = @import("executable.zig");
const proposals = @import("proposals.zig");
pub const Value = program.value.Value;
pub const Error = kernel.Error || client.Error || bindings.Error || values.Error ||
    primitives.Error || executable.Error || error{ LibraryMissing, ExecutableMissing };
pub const Library = struct { id: []const u8, source: program.worker.Source };
pub const Stored = struct { reference: content.ContainerRef, body: content.Body };
pub const Diagnostic = struct { object: []const u8, code: []const u8, message: []const u8 };

pub const Context = struct {
    executable: []const u8,
    verified_executable: ?executable.Input = null,
    running_executable: ?[]const u8 = null,
    worker_arguments: []const []const u8 = &.{"--component-worker"},
    libraries: []const Library,
    fixed_content: []const Stored,
    cancel: ?*const std.atomic.Value(bool) = null,
    generated: std.ArrayList(Stored) = .empty,
    generated_bytes: u64 = 0,
    scratch: ?[]u8 = null,
    diagnostic: ?Diagnostic = null,

    pub fn evaluation(self: *Context) kernel.Evaluation {
        return .{ .context = self, .call = evaluate };
    }

    pub fn provider(self: *Context) kernel.ContentProvider {
        return .{ .context = self, .open = open };
    }

    fn evaluate(
        opaque_context: ?*anyopaque,
        arena: std.mem.Allocator,
        io: std.Io,
        request: kernel.Request,
    ) kernel.Error!kernel.EvaluationResult {
        const self: *Context = @ptrCast(@alignCast(opaque_context orelse
            return error.KernelEvaluation));
        self.diagnostic = null;
        return self.run(arena, io, request) catch |err| {
            if (self.diagnostic == null) self.diagnostic = .{
                .object = request.model.id,
                .code = @errorName(err),
                .message = @errorName(err),
            };
            if (err == error.Canceled) return error.Canceled;
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.KernelEvaluation;
        };
    }

    fn open(
        opaque_context: ?*anyopaque,
        _: std.mem.Allocator,
        _: std.Io,
        reference: content.ContainerRef,
    ) kernel.Error!content.Body {
        const self: *Context = @ptrCast(@alignCast(opaque_context orelse
            return error.KernelEvaluation));
        return self.findContent(reference) orelse error.KernelEvaluation;
    }

    pub fn findContent(self: *const Context, reference: content.ContainerRef) ?content.Body {
        for ([_][]const Stored{ self.fixed_content, self.generated.items }) |items| {
            for (items) |item| {
                if (item.reference.format == reference.format and
                    item.reference.bytes == reference.bytes and
                    std.mem.eql(u8, &item.reference.sha256, &reference.sha256)) return item.body;
            }
        }
        return null;
    }

    pub fn run(
        self: *Context,
        arena: std.mem.Allocator,
        io: std.Io,
        request: kernel.Request,
    ) Error!kernel.EvaluationResult {
        self.generated = .empty;
        self.generated_bytes = 0;
        self.scratch = null;
        self.diagnostic = null;
        self.running_executable = null;
        try program.model.validate(request.model);
        if (self.libraries.len > contracts.limits.default.program_items or
            self.fixed_content.len > contracts.limits.default.program_items)
            return error.KernelLimit;
        const snapshot = if (request.model.calls.len == 0) null else try executable.capture(
            arena,
            io,
            request.workspace,
            self.verified_executable orelse return error.ExecutableMissing,
            self.cancel,
        );
        defer if (snapshot) |owned| owned.deinit(io);
        if (snapshot) |owned| self.running_executable = owned.path;
        defer self.running_executable = null;
        return self.graph(arena, io, request);
    }

    fn graph(
        self: *Context,
        arena: std.mem.Allocator,
        io: std.Io,
        request: kernel.Request,
    ) Error!kernel.EvaluationResult {
        var observed: std.ArrayList(bindings.Result) = .empty;
        for (request.model.observations) |observation| {
            try observed.append(arena, .{
                .id = observation.id,
                .value = try primitives.observe(observation),
            });
        }
        var results: std.ArrayList(bindings.Result) = .empty;
        var states: std.ArrayList(kernel.CallResult) = .empty;
        var containers: std.ArrayList(kernel.DesiredContainer) = .empty;
        var migrations: std.ArrayList(kernel.Migration) = .empty;
        for (try program.model.order(arena, request.model)) |index| {
            const call = request.model.calls[index];
            const previous_state = try self.previous(arena, io, request, call, &migrations);
            var resolver: bindings.Resolver = .{
                .arena = arena,
                .inputs = request.inputs,
                .results = results.items,
                .observations = observed.items,
                .previous = previous_state,
            };
            const arguments = try arena.alloc(Value, call.arguments.len);
            for (call.arguments, arguments) |binding, *argument| {
                argument.* = try resolver.resolve(binding, 0);
            }
            const output = try self.invoke(
                arena,
                io,
                request.workspace,
                call.id,
                call.library,
                call.interface,
                call.function,
                arguments,
            );
            if (call.result_role == .value) {
                if (output) |value| try results.append(arena, .{ .id = call.id, .value = value });
                continue;
            }
            const plan = try values.unwrap(output orelse return error.ValueInvalid);
            const normalized = try proposals.freeze(self, arena, io, call, plan, &containers);
            const state = try values.field(normalized, "state");
            if (state != .option) return error.ValueInvalid;
            try states.append(arena, .{
                .call = call.id,
                .value = if (state.option) |v| v.* else null,
            });
            try results.append(arena, .{ .id = call.id, .value = normalized });
        }
        return .{
            .containers = containers.items,
            .states = states.items,
            .migrations = migrations.items,
        };
    }

    fn previous(
        self: *Context,
        arena: std.mem.Allocator,
        io: std.Io,
        request: kernel.Request,
        call: program.model.Call,
        receipts: *std.ArrayList(kernel.Migration),
    ) Error!Value {
        const current = request.current orelse return .{ .option = null };
        const old = program.find(kernel.CallState, current.calls, call.id) orelse
            return .{ .option = null };
        var state = old.value orelse return .{ .option = null };
        for (request.selected_migrations) |migration| {
            if (!std.mem.eql(u8, migration.call, call.id)) continue;
            const rule = migration.rule;
            const converted = try self.invoke(
                arena,
                io,
                request.workspace,
                rule.id,
                rule.library,
                rule.interface,
                rule.function,
                &.{state},
            );
            state = try values.unwrap(converted orelse return error.ValueInvalid);
            try receipts.append(arena, migration);
        }
        const result = try arena.create(Value);
        result.* = state;
        return .{ .option = result };
    }

    fn invoke(
        self: *Context,
        arena: std.mem.Allocator,
        io: std.Io,
        workspace: std.Io.Dir,
        object: []const u8,
        library: []const u8,
        interface: []const u8,
        function: []const u8,
        arguments: []const Value,
    ) Error!?Value {
        const source = program.find(Library, self.libraries, library) orelse
            return error.LibraryMissing;
        const worker: client.Client = .{
            .executable = self.running_executable orelse return error.ExecutableMissing,
            .arguments = self.worker_arguments,
            .workspace = workspace,
            .cancel = self.cancel,
        };
        const response = worker.call(arena, io, .{
            .action = .invoke,
            .source = self.librarySource(source.source),
            .interface = interface,
            .function = function,
            .args = arguments,
        }) catch |err| {
            self.diagnostic = .{
                .object = object,
                .code = @errorName(err),
                .message = @errorName(err),
            };
            return err;
        };
        if (response.status == .@"error") {
            const reported = response.@"error" orelse return error.WorkerProtocol;
            self.diagnostic = .{
                .object = object,
                .code = reported.code,
                .message = reported.message,
            };
            return error.GuestRejected;
        }
        return response.result;
    }

    fn librarySource(self: *const Context, source: program.worker.Source) program.worker.Source {
        var resolved = source;
        switch (resolved) {
            .file => |*file| if (std.mem.eql(u8, file.path, self.executable)) {
                file.path = self.running_executable orelse return source;
            },
            .range => |*range| if (std.mem.eql(u8, range.path, self.executable)) {
                range.path = self.running_executable orelse return source;
            },
        }
        return resolved;
    }
};

test {
    _ = bindings;
    _ = values;
    _ = proposals;
    _ = executable;
}

test "N2-EVAL-05: a reused evaluator cannot resolve a prior evaluation's generated reference" {
    var earlier: std.heap.ArenaAllocator = .init(std.testing.allocator);
    const bytes = try earlier.allocator().dupe(u8, "old-generated-content");
    var context: Context = .{
        .executable = "/fixed-runtime",
        .libraries = &.{},
        .fixed_content = &.{},
    };
    const reference: content.ContainerRef = .{ .sha256 = @splat(1), .bytes = bytes.len };
    try context.generated.append(earlier.allocator(), .{
        .reference = reference,
        .body = content.Body.bytes(bytes),
    });
    context.generated_bytes = bytes.len;
    context.scratch = bytes;
    earlier.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var workspace = std.testing.tmpDir(.{});
    defer workspace.cleanup();
    const result = try context.run(arena.allocator(), std.testing.io, .{
        .model = .{
            .id = "empty",
            .release_sequence = 1,
            .target = .@"aarch64-macos",
            .profile = .{ .id = "profile", .target = .@"aarch64-macos", .primitives = &.{} },
        },
        .current = null,
        .inputs = &.{},
        .action = .install,
        .selected_migrations = &.{},
        .workspace = workspace.dir,
    });
    try std.testing.expectEqual(@as(usize, 0), result.containers.len);
    try std.testing.expectEqual(@as(u64, 0), context.generated_bytes);
    try std.testing.expect(context.findContent(reference) == null);
    try std.testing.expect(context.scratch == null);
}
