//! Bounded disposable-worker orchestration, shared by the compiler and native runtime.
const std = @import("std");
const program = @import("program");
const contracts = @import("contracts");
pub const protocol = program.worker;
const limits = contracts.limits.default;

pub const Error = contracts.json.DecodeError || program.value.Error || error{
    WorkerIo,
    WorkerLaunch,
    WorkerExit,
    WorkerBudget,
    WorkerTimeout,
    WorkerProtocol,
    WorkerLimit,
    Canceled,
    ConcurrencyUnavailable,
};
pub const Client = struct {
    /// Absolute path to the published helper or current precompiled setup executable.
    executable: []const u8,
    arguments: []const []const u8 = &.{},
    /// Caller owns a private directory for the entire invocation.
    workspace: std.Io.Dir,
    cancel: ?*const std.atomic.Value(bool) = null,

    pub fn call(
        self: Client,
        arena: std.mem.Allocator,
        io: std.Io,
        request: protocol.Request,
    ) Error!protocol.Response {
        if (!std.fs.path.isAbsolute(self.executable) or self.arguments.len > 8)
            return error.WorkerProtocol;
        if (self.cancel) |flag| if (flag.load(.acquire)) return error.Canceled;
        const bytes = try encode(arena, request);
        var nonce: [16]u8 = undefined; // SAFETY: random fills the filename suffix.
        io.random(&nonce);
        const name = try arena.print("worker-{s}.input", .{std.fmt.bytesToHex(nonce, .lower)});
        const input = self.workspace.createFile(io, name, .{
            .read = true,
            .exclusive = true,
            .permissions = if (std.Io.File.Permissions.has_executable_bit)
                .fromMode(0o600)
            else
                .default_file,
        }) catch return error.WorkerIo;
        defer self.workspace.deleteFile(io, name) catch |err| {
            std.log.warn("worker input cleanup: {s}", .{@errorName(err)});
        };
        defer input.close(io);
        input.writePositionalAll(io, bytes, 0) catch return error.WorkerIo;
        const timeout: std.Io.Timeout = .{ .duration = .{
            .raw = .fromSeconds(30),
            .clock = .awake,
        } };
        const deadline = timeout.toDeadline(io);
        const Event = union(enum) { response: Error!protocol.Response, deadline: Error!void };
        var events: [2]Event = undefined; // SAFETY: Select initializes queued events before reads.
        var selection = std.Io.Select(Event).init(io, &events);
        defer selection.cancelDiscard();
        selection.concurrent(.deadline, watch, .{ io, self.cancel, deadline }) catch
            return error.ConcurrencyUnavailable;
        selection.async(.response, exchange, .{ self, arena, io, input, request.action, deadline });
        return switch (try selection.await()) {
            .response => |response| response,
            .deadline => |result| {
                try result;
                return error.WorkerTimeout;
            },
        };
    }
};

fn encode(arena: std.mem.Allocator, request: protocol.Request) Error![]const u8 {
    if (request.schema != 1 or request.args.len > limits.program_items or
        request.allowed_imports.len > limits.program_items) return error.WorkerProtocol;
    for (request.args) |argument| try program.value.validate(argument, .{});
    const storage = try arena.alloc(u8, limits.program_bytes);
    var writer: std.Io.Writer = .fixed(storage);
    std.json.Stringify.value(request, .{}, &writer) catch return error.WorkerLimit;
    return writer.buffered();
}

fn watch(
    io: std.Io,
    flag: ?*const std.atomic.Value(bool),
    deadline: std.Io.Timeout,
) Error!void {
    std.debug.assert(deadline == .deadline);
    for (0..300) |_| {
        if (flag) |cancel| if (cancel.load(.acquire)) return error.Canceled;
        if (deadline.deadline.untilNow(io).raw.nanoseconds >= 0) return error.WorkerTimeout;
        try std.Io.sleep(io, .fromMilliseconds(100), .awake);
    }
    return error.WorkerTimeout;
}

fn exchange(
    self: Client,
    arena: std.mem.Allocator,
    io: std.Io,
    input: std.Io.File,
    action: @FieldType(protocol.Request, "action"),
    deadline: std.Io.Timeout,
) Error!protocol.Response {
    std.debug.assert(self.arguments.len <= 8);
    var argv: [9][]const u8 = undefined; // SAFETY: only the initialized prefix reaches spawn.
    argv[0] = self.executable;
    @memcpy(argv[1 .. self.arguments.len + 1], self.arguments);
    var child = std.process.spawn(io, .{
        .argv = argv[0 .. self.arguments.len + 1],
        .stdin = .{ .file = input },
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch |err| return if (err == error.Canceled) error.Canceled else error.WorkerLaunch;
    defer child.kill(io);
    var buffer: std.Io.File.MultiReader.Buffer(2) = undefined; // SAFETY: init owns the buffer.
    var reader: std.Io.File.MultiReader = undefined; // SAFETY: init initializes all state.
    reader.init(arena, io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    try collect(&reader, deadline);
    const term = child.wait(io) catch |err|
        return if (err == error.Canceled) error.Canceled else error.WorkerIo;
    const stdout = try reader.toOwnedSlice(0);
    const stderr = try reader.toOwnedSlice(1);
    if (!term.success()) {
        if (std.mem.indexOf(u8, stderr, "NIOBIUM_COMPONENT_ALLOCATION_LIMIT") != null)
            return error.WorkerBudget;
        return error.WorkerExit;
    }
    const response = try contracts.json.decode(protocol.Response, arena, stdout, .{
        .max_bytes = limits.component_output_bytes,
        .max_schema = 1,
        .limits = .{ .json_depth = program.model.wire_depth },
    });
    try validate(response, action);
    return response;
}

fn collect(reader: *std.Io.File.MultiReader, deadline: std.Io.Timeout) Error!void {
    for (0..4096) |_| {
        reader.fill(64, deadline) catch |err| switch (err) {
            error.EndOfStream => {
                reader.checkAnyError() catch return error.WorkerIo;
                return;
            },
            error.Canceled => return error.Canceled,
            error.Timeout => return error.WorkerTimeout,
            error.ConcurrencyUnavailable => return error.ConcurrencyUnavailable,
        };
        if (reader.reader(0).buffered().len > limits.component_output_bytes or
            reader.reader(1).buffered().len > limits.component_output_bytes)
            return error.WorkerLimit;
    }
    return error.WorkerLimit;
}

fn validate(
    response: protocol.Response,
    action: @FieldType(protocol.Request, "action"),
) Error!void {
    if (response.schema != 1) return error.WorkerProtocol;
    if (response.status == .@"error") {
        if (response.@"error" == null or response.result != null or response.inspection != null)
            return error.WorkerProtocol;
        return;
    }
    if (response.@"error" != null) return error.WorkerProtocol;
    switch (action) {
        .inspect => if (response.inspection == null or response.result != null)
            return error.WorkerProtocol,
        .invoke => if (response.inspection != null) return error.WorkerProtocol,
    }
    if (response.result) |value| try program.value.validate(value, .{});
}

test "N2-COMPONENT-02: process response shape is checked before consumption" {
    try std.testing.expectError(error.WorkerProtocol, validate(.{ .status = .ok }, .inspect));
    try std.testing.expectError(error.WorkerProtocol, validate(.{
        .status = .@"error",
        .result = .{ .boolean = true },
    }, .invoke));
    try validate(.{ .status = .ok, .result = .{ .uint64 = std.math.maxInt(u64) } }, .invoke);
}
