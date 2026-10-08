//! Read-only native decoder witness for schema fixtures and actual persisted records.
const std = @import("std");
const kernel = @import("kernel");
const program = @import("program");
const access = @import("access");
const contracts = @import("contracts");
const limits = contracts.limits.default;
const Kind = enum { state, plan, owner, prepared };

pub fn main(init: std.process.Init) void {
    execute(init) catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn execute(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 3 and args.len != 4) return error.Usage;
    const kind = std.meta.stringToEnum(Kind, args[1]) orelse return error.Usage;
    const bytes = try read(arena, init.io, args[2]);
    const owner_bytes = if (args.len == 4) try read(arena, init.io, args[3]) else null;
    try check(arena, kind, bytes, owner_bytes);
    try std.Io.File.stdout().writeStreamingAll(init.io, "{\"status\":\"PASS\"}\n");
}

fn read(arena: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(limits.runtime_plan_bytes));
}

fn check(
    arena: std.mem.Allocator,
    kind: Kind,
    bytes: []const u8,
    owner_bytes: ?[]const u8,
) !void {
    switch (kind) {
        .state, .plan => {
            const ownership = try kernel.wire.decode(kernel.Owner, arena, owner_bytes orelse
                return error.Usage);
            try kernel.wire.owner(ownership, ownership);
            if (kind == .state) {
                const value = try kernel.wire.decode(kernel.Snapshot, arena, bytes);
                try kernel.wire.snapshot(arena, value, ownership);
            } else {
                const value = try kernel.wire.decode(kernel.Plan, arena, bytes);
                try kernel.wire.plan(arena, value, ownership);
            }
        },
        .owner => {
            const value = try kernel.wire.decode(kernel.Owner, arena, bytes);
            try kernel.wire.owner(value, value);
        },
        .prepared => {
            const value = try kernel.wire.decode(kernel.Prepared, arena, bytes);
            if (value.schema != 2) return error.KernelUnsupported;
            try kernel.wire.hash(value.plan_sha256);
            try program.validation.identifier(value.root);
            if (value.receipts.len > limits.files_per_artifact) return error.KernelLimit;
            for (value.receipts) |receipt| {
                try kernel.wire.path(receipt.path);
                if (receipt.link_target.len != 0) try kernel.wire.linkTarget(receipt.link_target);
                if (receipt.access_hex.len != 0) {
                    const encoded = try program.decodeHex(arena, receipt.access_hex);
                    const decoded = try access.decodeReceipt(arena, encoded);
                    try access.validate(decoded.policy);
                }
            }
        },
    }
}

const ownership_fixture: kernel.Owner = .{
    .instance = "00000000000000000000000000000000",
    .product_id = "wire-test",
    .root = "application",
    .state_root = "application",
    .roots = &.{.{
        .id = "application",
        .path = if (@import("builtin").os.tag == .windows) "C:\\owned" else "/owned",
    }},
};

fn owner() kernel.Owner {
    return ownership_fixture;
}

const snapshot_fixture: kernel.Snapshot = .{
    .instance = ownership_fixture.instance,
    .product_id = "wire-test",
    .release_sequence = 1,
    .model_version = 1,
    .program_sha256 = "0000000000000000000000000000000000000000000000000000000000000000",
    .inputs = &.{.{ .id = "enabled", .value = .{ .boolean = true } }},
    .calls = &.{.{
        .id = "deploy",
        .library = "library",
        .interface = "",
        .function = "build",
        .implementation_sha256 = "0000000000000000000000000000000000000000000000000000000000000000",
        .version = 1,
        .value = null,
    }},
    .migrations = &.{},
    .roots = &.{.{
        .id = "application",
        .generation = ownership_fixture.instance,
        .resources = &.{},
    }},
};

fn snapshot() kernel.Snapshot {
    return snapshot_fixture;
}

fn plan() kernel.Plan {
    return .{
        .instance = owner().instance,
        .product_id = "wire-test",
        .transaction = owner().instance,
        .roots = owner().roots,
        .state_root = owner().state_root,
        .previous = null,
        .next = snapshot(),
        .containers = &.{},
    };
}

test "N2-KERNEL-SCHEMA-01 nullable owners and strict plan decoding remain bounded" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ownership = try kernel.wire.encode(a, owner());
    const state = try kernel.wire.encode(a, snapshot());
    const encoded_plan = try kernel.wire.encode(a, plan());
    try check(a, .state, state, ownership);
    try check(a, .plan, encoded_plan, ownership);
    const extra = try std.mem.concat(a, u8, &.{ "{\"unknown\":0,", encoded_plan[1..] });
    try std.testing.expectError(error.JsonUnknownField, check(a, .plan, extra, ownership));
    var changed = plan();
    changed.schema = 99;
    try std.testing.expectError(
        error.UnsupportedSchema,
        check(a, .plan, try std.json.Stringify.valueAlloc(a, changed, .{}), ownership),
    );
    changed = plan();
    changed.host_abi = 99;
    try std.testing.expectError(
        error.KernelUnsupported,
        check(a, .plan, try kernel.wire.encode(a, changed), ownership),
    );
    const oversized = try a.alloc(u8, limits.runtime_plan_bytes + 1);
    @memset(oversized, ' ');
    try std.testing.expectError(error.JsonTooLarge, check(a, .plan, oversized, ownership));
}

test "N2-KERNEL-SCHEMA-01 native checks reject foreign identity and immutable history changes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ownership = try kernel.wire.encode(a, owner());
    var state = snapshot();
    state.instance = "ffffffffffffffffffffffffffffffff";
    try std.testing.expectError(
        error.KernelOwnership,
        check(a, .state, try kernel.wire.encode(a, state), ownership),
    );
    state = snapshot();
    state.model_version = 3;
    state.model_migrations = &.{
        .{ .id = "one", .from = 1, .to = 2 }, .{ .id = "two", .from = 1, .to = 3 },
    };
    try std.testing.expectError(
        error.KernelState,
        check(a, .state, try kernel.wire.encode(a, state), ownership),
    );
}

test "N2-KERNEL-SCHEMA-01 native receipt identities preserve all 128 bits" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value: kernel.Prepared = .{
        .plan_sha256 = snapshot().program_sha256,
        .root = "application",
        .receipts = &.{.{
            .path = "link",
            .link_inode = std.math.maxInt(u128),
            .link_target = "data",
        }},
    };
    const bytes = try kernel.wire.encode(a, value);
    try check(a, .prepared, bytes, null);
    const decoded = try kernel.wire.decode(kernel.Prepared, a, bytes);
    try std.testing.expectEqual(std.math.maxInt(u128), decoded.receipts[0].link_inode);
}

test "N2-KERNEL-SCHEMA-02 encoder cannot emit a state its bounded decoder rejects" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try a.alloc(u8, limits.access_acl_bytes * 2 + 1);
    @memset(text, 'x');
    var state = snapshot();
    state.inputs = &.{.{ .id = "large", .value = .{ .text = text } }};
    try program.value.validate(state.inputs[0].value, .{});
    if (kernel.wire.encode(a, state)) |_| {
        return error.TestUnexpectedResult;
    } else |err| {
        try std.testing.expect(err == error.JsonStringTooLong);
    }
}
