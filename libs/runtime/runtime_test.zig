//! Native filesystem checks for frozen-plan recovery; guest execution is intentionally absent.

const std = @import("std");
const program = @import("program");
const storage = @import("storage.zig");
const state = @import("state.zig");
const transaction = @import("transaction.zig");
const runtime = @import("root.zig");

const owner: state.Owner = .{
    .product_id = "example.test",
    .root_id = "0123456789abcdef0123456789abcdef",
};

fn plan(store: storage.Storage, previous: ?state.Snapshot, text: []const u8) !state.Plan {
    const generation = if (previous) |old| old.generation + 1 else 1;
    const files = try store.arena.alloc(state.File, 1);
    files[0] = .{
        .id = "environment",
        .path = "environment.txt",
        .sha256 = try program.digest(store.arena, text),
        .data_hex = try program.encodeHex(store.arena, text),
    };
    const resources = try store.arena.alloc(state.Resource, 1);
    resources[0] = .{ .id = files[0].id, .path = files[0].path, .sha256 = files[0].sha256 };
    return .{
        .root_id = owner.root_id,
        .root_path = store.path,
        .product_id = owner.product_id,
        .generation = generation,
        .previous = previous,
        .next = .{
            .root_id = owner.root_id,
            .product_id = owner.product_id,
            .generation = generation,
            .release_sequence = generation,
            .model_version = 1,
            .program_sha256 = try program.digest(store.arena, "program"),
            .inputs = &.{},
            .instances = &.{},
            .migrations = &.{},
            .resources = resources,
        },
        .files = files,
    };
}

test "N2-REC-01: uncommitted pointer swap rolls back using frozen plan" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try temp.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const root = try std.fs.path.join(arena.allocator(), &.{ base, "install" });
    const store = try storage.Storage.open(std.testing.io, arena.allocator(), root);
    defer store.close();
    const old = try plan(store, null, "old");
    try transaction.apply(store, owner, old, .{});
    const new = try plan(store, old.next, "new");
    try store.write("pending.json", try state.encode(store.arena, new));
    try store.write("generations/2/.niobium-generation", try state.encode(store.arena, new.next));
    try store.write("generations/2/environment.txt", "new");
    try store.pointer(2);
    try std.testing.expect(try transaction.recover(store, owner));
    try std.testing.expectEqualStrings("generations/1", (try store.readPointer()).?);
    try std.testing.expectEqualStrings(
        "old",
        (try store.read("generations/1/environment.txt", 32)).?,
    );
    try std.testing.expect(try store.read("generations/2/environment.txt", 32) == null);
    try std.testing.expect(!try transaction.recover(store, owner));
}

test "N2-REC-01: committed plan rolls forward without guest or compiler" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try temp.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const root = try std.fs.path.join(arena.allocator(), &.{ base, "install" });
    const store = try storage.Storage.open(std.testing.io, arena.allocator(), root);
    defer store.close();
    const next = try plan(store, null, "materialized");
    try store.write("pending.json", try state.encode(store.arena, next));
    try store.write("committed", "commit-v1\n");
    try std.testing.expect(try transaction.recover(store, owner));
    try std.testing.expectEqualStrings("generations/1", (try store.readPointer()).?);
    try std.testing.expectEqualStrings(
        "materialized",
        (try store.read("generations/1/environment.txt", 64)).?,
    );
    try std.testing.expect(!try transaction.recover(store, owner));
    var unknown = next;
    unknown.host_abi = 2;
    try store.write("pending.json", try state.encode(store.arena, unknown));
    try std.testing.expectError(error.PlanUnsupported, transaction.recover(store, owner));
    try std.testing.expectEqualStrings("generations/1", (try store.readPointer()).?);
}

test "N2-SAFE-01: storage rejects directory traversal and symlink parents" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try temp.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const root = try std.fs.path.join(arena.allocator(), &.{ base, "install" });
    const store = try storage.Storage.open(std.testing.io, arena.allocator(), root);
    defer store.close();
    try std.testing.expectError(error.ProgramPath, store.write("../escaped", "bad"));
    try store.dir.symLink(std.testing.io, base, "outside", .{ .is_directory = true });
    if (store.write("outside/escaped", "bad")) |_| {
        return error.TestUnexpectedResult;
    } else |_| {}
    try std.testing.expectError(
        error.FileNotFound,
        temp.dir.access(std.testing.io, "escaped", .{}),
    );
}

test "N2-LIFE-01: cleanup preserves files absent from the ownership inventory" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try temp.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const root = try std.fs.path.join(arena.allocator(), &.{ base, "install" });
    const store = try storage.Storage.open(std.testing.io, arena.allocator(), root);
    defer store.close();
    const old = try plan(store, null, "old");
    try transaction.apply(store, owner, old, .{});
    try store.write("generations/1/notes.txt", "user-owned");
    try transaction.apply(store, owner, try plan(store, old.next, "new"), .{});
    try std.testing.expectEqualStrings(
        "user-owned",
        (try store.read("generations/1/notes.txt", 32)) orelse return error.TestUnexpectedResult,
    );
}

test "N2-SAFE-01: first install refuses an unowned nonempty root" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try temp.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "user.txt", .data = "keep" });
    const value: program.Program = .{
        .product_id = owner.product_id,
        .release_sequence = 1,
        .libraries = &.{.{
            .id = "library",
            .wasm_hex = try program.encodeHex(arena.allocator(), "wasm"),
            .sha256 = try program.digest(arena.allocator(), "wasm"),
        }},
        .instances = &.{.{ .id = "instance", .library = "library" }},
    };
    try std.testing.expectError(error.RootNotEmpty, runtime.run(.{
        .io = std.testing.io,
        .arena = arena.allocator(),
        .root = base,
        .action = .install,
        .model = value,
    }));
    try std.testing.expectError(
        error.FileNotFound,
        temp.dir.access(std.testing.io, "owner.json", .{}),
    );
}

test "N2-SAFE-01: transaction refuses a preexisting generation" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try temp.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const root = try std.fs.path.join(arena.allocator(), &.{ base, "install" });
    const store = try storage.Storage.open(std.testing.io, arena.allocator(), root);
    defer store.close();
    try store.write("generations/1/foreign.txt", "unowned");
    try std.testing.expectError(error.GenerationConflict, transaction.apply(
        store,
        owner,
        try plan(store, null, "new"),
        .{},
    ));
    try std.testing.expect(try store.read("pending.json", 4096) == null);
}

test "N2-REC-01: missing rollback source preserves the pending new generation" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try temp.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const root = try std.fs.path.join(arena.allocator(), &.{ base, "install" });
    const store = try storage.Storage.open(std.testing.io, arena.allocator(), root);
    defer store.close();
    const old = try plan(store, null, "old");
    try transaction.apply(store, owner, old, .{});
    const next = try plan(store, old.next, "new");
    try store.write("pending.json", try state.encode(store.arena, next));
    try store.write("generations/2/environment.txt", "new");
    try store.pointer(2);
    try store.remove("generations/1/.niobium-generation");
    try std.testing.expectError(error.StateInvalid, transaction.recover(store, owner));
    try std.testing.expectEqualStrings("generations/2", (try store.readPointer()).?);
    try std.testing.expectEqualStrings(
        "new",
        (try store.read("generations/2/environment.txt", 32)).?,
    );
}

test "N2-LIFE-01: concurrent transactions cannot acquire the same root" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try temp.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const store = try storage.Storage.open(std.testing.io, arena.allocator(), base);
    defer store.close();
    try std.testing.expectError(
        error.RuntimeBusy,
        storage.Storage.open(std.testing.io, arena.allocator(), base),
    );
}

test "N2-MIG-01: stored versions and direct transitions must be explicitly supported" {
    try std.testing.expectError(error.UpgradeUnsupported, state.transition(&.{}, 9, 2));
    try std.testing.expectError(error.ProgramDuplicate, program.validate(.{
        .product_id = "example.migration",
        .release_sequence = 2,
        .model_version = 2,
        .upgrades = &.{
            .{ .id = "one", .from = 1, .to = 2 },
            .{ .id = "two", .from = 1, .to = 2 },
        },
    }));
}

const empty_guest = "\x00asm\x01\x00\x00\x00" ++
    "\x01\x05\x01\x60\x00\x01\x7f" ++
    "\x03\x02\x01\x00" ++
    "\x05\x04\x01\x01\x01\x01" ++
    "\x07\x17\x02\x06memory\x02\x00\x0anb_plan_v1\x00\x00" ++
    "\x0a\x06\x01\x04\x00\x41\x00\x0b";

fn inputProgram() program.Program {
    return .{
        .product_id = owner.product_id,
        .release_sequence = 1,
        .inputs = &.{.{ .id = "sdk", .default = "stable" }},
    };
}

test "N2-MIG-01: persisted instance state cannot cross library identities" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var model = inputProgram();
    model.release_sequence = 2;
    const digest = try program.digest(a, empty_guest);
    model.libraries = &.{.{
        .id = "replacement",
        .wasm_hex = try program.encodeHex(a, empty_guest),
        .sha256 = digest,
    }};
    model.instances = &.{.{ .id = "instance", .library = "replacement" }};
    const previous: state.Snapshot = .{
        .root_id = owner.root_id,
        .product_id = owner.product_id,
        .generation = 1,
        .release_sequence = 1,
        .model_version = 1,
        .program_sha256 = try program.digest(a, "previous-program"),
        .inputs = &.{},
        .instances = &.{.{
            .id = "instance",
            .library_id = "original",
            .library_sha256 = digest,
            .version = 1,
            .data_hex = try program.encodeHex(a, "original-private-state"),
        }},
        .migrations = &.{},
    };
    try std.testing.expectError(
        error.LibraryIdentityMismatch,
        runtime.evaluation.prepare(a, model, owner, "/test", previous, &.{}),
    );
    const updated_guest = empty_guest ++ "\x00\x01\x00";
    model.libraries = &.{.{
        .id = "original",
        .wasm_hex = try program.encodeHex(a, updated_guest),
        .sha256 = try program.digest(a, updated_guest),
    }};
    model.instances = &.{.{ .id = "instance", .library = "original" }};
    const accepted = try runtime.evaluation.prepare(a, model, owner, "/test", previous, &.{});
    const instance = (accepted.next orelse return error.TestUnexpectedResult).instances[0];
    try std.testing.expectEqualStrings(previous.instances[0].data_hex, instance.data_hex);
    try std.testing.expect(!std.mem.eql(
        u8,
        previous.instances[0].library_sha256,
        instance.library_sha256,
    ));
}

test "N2-SAFE-01: runtime overrides and durable snapshot inputs must be UTF-8" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const model = inputProgram();
    for ([_][]const u8{ "\xff", "\xc0\x80", "\xed\xa0\x80", "\xe2\x82" }) |invalid| {
        try std.testing.expectError(error.ProgramInvalid, runtime.evaluation.prepare(
            a,
            model,
            owner,
            "/test",
            null,
            &.{.{ .id = "sdk", .value = invalid }},
        ));
    }
    const prepared = try runtime.evaluation.prepare(a, model, owner, "/test", null, &.{});
    var snapshot = prepared.next orelse return error.TestUnexpectedResult;
    snapshot.inputs = &.{.{ .id = "sdk", .value = "\xff" }};
    try std.testing.expectError(error.ProgramInvalid, state.validateSnapshot(snapshot, owner));
    try std.testing.expectError(
        error.ProgramInvalid,
        runtime.evaluation.prepare(a, model, owner, "/test", snapshot, &.{}),
    );
}

test "N2-LIFE-01: Unicode runtime input roundtrips through durable state" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = "工具链 café 🦀";
    const model = inputProgram();
    const selected: []const state.Value = &.{.{ .id = "sdk", .value = text }};
    const prepared = try runtime.evaluation.prepare(a, model, owner, "/test", null, selected);
    const snapshot = prepared.next orelse return error.TestUnexpectedResult;
    const decoded = try state.decode(state.Snapshot, a, try state.encode(a, snapshot));
    try state.validateSnapshot(decoded, owner);
    try std.testing.expectEqualStrings(text, decoded.inputs[0].value);
    const reapplied = try runtime.evaluation.prepare(a, model, owner, "/test", decoded, &.{});
    const retained = (reapplied.next orelse return error.TestUnexpectedResult).inputs[0].value;
    try std.testing.expectEqualStrings(text, retained);
}

test "N2-SAFE-01: durable plan root paths must be UTF-8" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const invalid: state.Plan = .{
        .root_id = owner.root_id,
        .root_path = "/bad\xff/path",
        .product_id = owner.product_id,
        .generation = 1,
        .previous = null,
        .next = null,
        .files = &.{},
    };
    try std.testing.expectError(error.StateInvalid, state.validatePlan(
        arena.allocator(),
        invalid,
        owner,
        invalid.root_path,
    ));
}
