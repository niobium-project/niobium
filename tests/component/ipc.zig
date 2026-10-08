//! Exercise the production stdin/stdout protocol, not the in-process test adapter.
const std = @import("std");
const program = @import("program");
const client = @import("component_client");
const protocol = program.worker;
const provenance = @import("suite_provenance");
const Value = program.value.Value;
const Dir = std.Io.Dir;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var run = try provenance.Run.startForSuite(arena, init.io, args, "component-ipc");
    qualify(&run, args) catch |err| {
        try run.finish(@errorName(err));
        return err;
    };
    try run.finish(null);
    std.log.info("Component IPC evidence: {s}", .{run.evidence});
}

fn qualify(run: *provenance.Run, args: []const []const u8) !void {
    try run.capture();
    if (args.len != 9) return error.Usage;
    const source = try sourceFile(run, args[2]);
    var request: protocol.Request = .{ .action = .inspect, .source = .{ .file = source } };
    const inspection = try invoke(run, args[1], "inspect", request);
    try std.testing.expectEqual(.ok, inspection.status);
    const reflected = inspection.inspection orelse return error.MissingInspection;
    try std.testing.expectEqual(@as(usize, 1), reflected.imports.len);
    try std.testing.expect(try program.wit.isTypeOnlyImport(reflected.imports[0]));
    const interface = "niobium:reference/installer@1.0.0";
    const signature = try program.wit.findFunction(reflected.exports, interface, "build");
    try std.testing.expectEqual(@as(usize, 1), signature.params.len);
    request.action = .invoke;
    request.interface = interface;
    request.function = "exact";
    request.args = &.{.{ .uint64 = std.math.maxInt(u64) }};
    const exact = try invoke(run, args[1], "exact", request);
    try std.testing.expectEqual(std.math.maxInt(u64), exact.result.?.uint64);
    request.args = &.{.{ .uint32 = 1 }};
    try rejected(try invoke(run, args[1], "wrong-type", request), "WitTypeMismatch");
    request.function = "missing";
    try rejected(try invoke(run, args[1], "missing", request), "WitFunctionMissing");
    request.function = "[constructor]token";
    try rejected(try invoke(run, args[1], "resource", request), "WorkerResource");
    request.function = "encoded-output";
    request.args = &.{.{ .uint32 = 20000 }};
    try rejected(try invoke(run, args[1], "encoded-limit", request), "WorkerOutput");
    request.source.file.sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    try rejected(try invoke(run, args[1], "digest", request), "WorkerDigest");
    request.source = .{ .file = source };
    try plans(run, args[1], request, 1);
    var release_two = request;
    release_two.source = .{ .file = try sourceFile(run, args[8]) };
    try plans(run, args[1], release_two, 2);
    try clientFailures(run, args[5..8], source);
    try official(run, args[1], try sourceFile(run, args[4]));
    request.source = .{ .file = try sourceFile(run, args[3]) };
    request.interface = "";
    request.function = "exact";
    request.args = &.{.{ .uint64 = std.math.maxInt(u64) }};
    const direct = try invoke(run, args[1], "direct-world", request);
    try std.testing.expectEqual(std.math.maxInt(u64), direct.result.?.uint64);
}

fn plans(run: *provenance.Run, worker: []const u8, base: protocol.Request, version: u32) !void {
    var request = base;
    request.function = "build";
    const zeros: [32]u8 = @splat(0);
    const content: Value = .{ .record = &.{
        .{ .name = "format", .value = .{ .enumeration = "posix-pax-v1" } },
        .{ .name = "sha256", .value = .{ .bytes = &zeros } },
        .{ .name = "bytes", .value = .{ .uint64 = 10240 } },
    } };
    var fields = [_]program.value.Field{
        .{ .name = "previous", .value = .{ .option = null } },
        .{ .name = "enabled", .value = .{ .boolean = true } },
        .{ .name = "content", .value = content },
        .{ .name = "label", .value = .{ .text = "Toolchain" } },
        .{ .name = "platform", .value = .{ .text = "aarch64-macos" } },
        .{ .name = "prefix", .value = .{ .text = "toolchain" } },
        .{ .name = "grant", .value = .{ .text = "owned" } },
        .{ .name = "root", .value = .{ .text = "application" } },
    };
    request.args = &.{.{ .record = &fields }};
    const enabled_name = try run.arena.print("v{d}-enabled", .{version});
    const enabled = try invoke(run, worker, enabled_name, request);
    const plan = enabled.result.?.result.payload.?.*;
    try generatedPlan(plan, version);
    fields[1].value.boolean = false;
    const disabled = try invoke(
        run,
        worker,
        try run.arena.print("v{d}-disabled", .{version}),
        request,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        (try program.value.select(disabled.result.?.result.payload.?.*, &.{"containers"})).list.len,
    );
    request.function = "upgrade-state";
    request.args = &.{.{ .text = "enabled" }};
    const migrated = try invoke(
        run,
        worker,
        try run.arena.print("v{d}-migration", .{version}),
        request,
    );
    try std.testing.expectEqualStrings("v2:enabled", migrated.result.?.text);
    var state = migrated.result.?;
    fields[0].value.option = &state;
    request.function = "build";
    request.args = &.{.{ .record = &fields }};
    const updated = try invoke(
        run,
        worker,
        try run.arena.print("v{d}-migrated-plan", .{version}),
        request,
    );
    const private = try program.value.select(updated.result.?.result.payload.?.*, &.{"state"});
    try std.testing.expectEqualStrings("v2:disabled", private.option.?.text);
    if (version == 2) {
        state = .{ .text = "enabled" };
        const rejected_state = try invoke(run, worker, "v2-unconverted", request);
        try std.testing.expectEqual(.ok, rejected_state.status);
        try std.testing.expect(!rejected_state.result.?.result.success);
    }
}

fn generatedPlan(plan: Value, version: u32) !void {
    const initial_state = try program.value.select(plan, &.{"state"});
    try std.testing.expectEqualStrings(
        if (version == 2) "v2:enabled" else "enabled",
        initial_state.option.?.text,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        (try program.value.select(plan, &.{"containers"})).list.len,
    );
    const containers = try program.value.select(plan, &.{"containers"});
    const generated = try program.value.select(containers.list[0], &.{"container"});
    try std.testing.expectEqualStrings("generated", generated.variant.name);
    const first_entry = generated.variant.payload.?.list[0];
    const body = try program.value.select(first_entry, &.{"kind"});
    try std.testing.expectEqualStrings("file", body.variant.name);
    try std.testing.expectEqualStrings(
        "label=Toolchain\nplatform=aarch64-macos\nsource-bytes=10240\nprevious=none\n",
        body.variant.payload.?.bytes,
    );
}

fn sourceFile(run: *provenance.Run, path: []const u8) !protocol.FileSource {
    const bytes = try Dir.cwd().readFileAlloc(run.io, path, run.arena, .limited(4 << 20));
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    return .{
        .path = path,
        .length = std.math.cast(u32, bytes.len) orelse return error.TooLarge,
        .sha256 = try run.arena.dupe(u8, &std.fmt.bytesToHex(hash, .lower)),
    };
}

fn invoke(
    run: *provenance.Run,
    worker: []const u8,
    name: []const u8,
    request: protocol.Request,
) !protocol.Response {
    const encoded = try std.json.Stringify.valueAlloc(run.arena, request, .{});
    const path = try run.arena.print("{s}/{s}-request.json", .{ run.evidence, name });
    try Dir.cwd().writeFile(run.io, .{ .sub_path = path, .data = encoded });
    const workspace = try Dir.cwd().openDir(run.io, run.evidence, .{});
    defer workspace.close(run.io);
    const caller: client.Client = .{ .executable = worker, .workspace = workspace };
    const response = try caller.call(run.arena, run.io, request);
    try Dir.cwd().writeFile(run.io, .{
        .sub_path = try run.arena.print("{s}/{s}-response.json", .{ run.evidence, name }),
        .data = try std.json.Stringify.valueAlloc(run.arena, response, .{}),
    });
    return response;
}

fn rejected(response: protocol.Response, code: []const u8) !void {
    try std.testing.expectEqual(.@"error", response.status);
    try std.testing.expectEqualStrings(code, response.@"error".?.code);
}

fn official(run: *provenance.Run, worker: []const u8, source: protocol.FileSource) !void {
    const zeros: [32]u8 = @splat(0);
    const content: Value = .{ .record = &.{
        .{ .name = "format", .value = .{ .enumeration = "posix-pax-v1" } },
        .{ .name = "sha256", .value = .{ .bytes = &zeros } },
        .{ .name = "bytes", .value = .{ .uint64 = 10240 } },
    } };
    try selection(run, worker, source, content);
    const rights: Value = .{ .record = &.{
        .{ .name = "read", .value = .{ .boolean = true } },
        .{ .name = "write", .value = .{ .boolean = false } },
        .{ .name = "execute", .value = .{ .boolean = false } },
    } };
    const fields = [_]program.value.Field{
        .{ .name = "root", .value = .{ .text = "application" } },
        .{ .name = "grant", .value = .{ .text = "owned" } },
        .{ .name = "prefix", .value = .{ .text = "files" } },
        .{ .name = "content", .value = content },
        .{ .name = "enabled", .value = .{ .boolean = true } },
        .{ .name = "file-access", .value = try accessValue(run.arena, rights, "file") },
        .{ .name = "directory-access", .value = try accessValue(run.arena, rights, "directory") },
    };
    const response = try invoke(run, worker, "official-files", .{
        .action = .invoke,
        .source = .{ .file = source },
        .interface = "niobium:files/installer@1.0.0",
        .function = "build",
        .args = &.{.{ .record = &fields }},
    });
    try std.testing.expectEqual(.ok, response.status);
    const containers = try program.value.select(
        response.result.?.result.payload.?.*,
        &.{"containers"},
    );
    try std.testing.expectEqual(@as(usize, 1), containers.list.len);
    const selected = try program.value.select(containers.list[0], &.{"container"});
    try std.testing.expectEqualStrings("reference", selected.variant.name);
    try std.testing.expectEqual(
        @as(u64, 10240),
        (try program.value.select(selected.variant.payload.?.*, &.{"bytes"})).uint64,
    );
}
fn accessValue(arena: std.mem.Allocator, rights: Value, kind: []const u8) !Value {
    const fields = try arena.dupe(program.value.Field, &.{
        .{ .name = "schema", .value = .{ .uint32 = 1 } },
        .{ .name = "kind", .value = .{ .enumeration = kind } },
        .{ .name = "owner", .value = rights },
        .{ .name = "everyone", .value = rights },
    });
    return .{ .record = fields };
}

fn clientFailures(
    run: *provenance.Run,
    executables: []const []const u8,
    source: protocol.FileSource,
) !void {
    const probe = executables[0];
    const qualifier = executables[1];
    const qualifier_guest = executables[2];
    const workspace = try Dir.cwd().openDir(run.io, run.evidence, .{});
    defer workspace.close(run.io);
    var caller: client.Client = .{ .executable = probe, .workspace = workspace };
    const inspect_request: protocol.Request = .{
        .action = .inspect,
        .source = .{ .file = source },
    };
    caller.arguments = &.{"shape"};
    try std.testing.expectError(
        error.WorkerProtocol,
        caller.call(run.arena, run.io, inspect_request),
    );
    caller.arguments = &.{"overflow"};
    try std.testing.expectError(error.WorkerLimit, caller.call(run.arena, run.io, inspect_request));
    const ready = try run.arena.print("{s}/cancel-ready", .{run.evidence});
    caller.arguments = &.{ "hang", ready };
    var flag: std.atomic.Value(bool) = .init(false);
    caller.cancel = &flag;
    var cancellation = try run.io.concurrent(cancelAfter, .{ run.io, &flag });
    defer cancellation.cancel(run.io) catch |err| std.log.warn(
        "cancel helper: {s}",
        .{@errorName(err)},
    );
    try std.testing.expectError(error.Canceled, caller.call(run.arena, run.io, inspect_request));
    try cancellation.await(run.io);
    const started = try Dir.cwd().statFile(run.io, ready, .{});
    try std.testing.expectEqual(@as(u64, 7), started.size);
    caller.cancel = null;
    const timeout_ready = try run.arena.print("{s}/timeout-ready", .{run.evidence});
    caller.arguments = &.{ "hang", timeout_ready };
    try std.testing.expectError(
        error.WorkerTimeout,
        caller.call(run.arena, run.io, inspect_request),
    );
    caller.executable = qualifier;
    caller.arguments = &.{ qualifier_guest, "amplification" };
    caller.cancel = null;
    // Same parent protocol handles an actual upstream allocator abort, not a synthetic marker.
    try std.testing.expectError(
        error.WorkerBudget,
        caller.call(run.arena, run.io, inspect_request),
    );
    try Dir.cwd().writeFile(run.io, .{
        .sub_path = try run.arena.print("{s}/client-boundary.json", .{run.evidence}),
        .data = try std.json.Stringify.valueAlloc(run.arena, .{
            .status = "PASS",
            .cases = &.{
                "shape",
                "output",
                "active-cancel",
                "deadline",
                "rust-allocation-amplification",
            },
            .qualifier = qualifier,
            .qualifier_guest = qualifier_guest,
            .probe = probe,
            .source = source,
        }, .{}),
    });
}
fn cancelAfter(io: std.Io, flag: *std.atomic.Value(bool)) !void {
    // lint-allow(no-sleep-in-tests): Delay cancellation to prove a running child is terminated.
    try std.Io.sleep(io, .fromMilliseconds(200), .awake);
    flag.store(true, .release);
}

fn selection(
    run: *provenance.Run,
    worker: []const u8,
    source: protocol.FileSource,
    primary: Value,
) !void {
    const fields = try run.arena.dupe(program.value.Field, primary.record);
    fields[2].value = .{ .uint64 = 4096 };
    const response = try invoke(run, worker, "official-selection", .{
        .action = .invoke,
        .source = .{ .file = source },
        .interface = "niobium:files/installer@1.0.0",
        .function = "select-content",
        .args = &.{ primary, .{ .record = fields }, .{ .boolean = false } },
    });
    try std.testing.expectEqual(.ok, response.status);
    const selected = try program.value.select(response.result.?, &.{"bytes"});
    try std.testing.expectEqual(@as(u64, 4096), selected.uint64);
}
