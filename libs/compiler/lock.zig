//! Exact dependency identities. Resolution produces this graph before common compilation.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");

pub const Error = program.Error || error{ LockUnsupported, LockCycle, LockMissing, LockMismatch };
pub const Kind = enum { runtime, runtime_metadata, library, content, tool };
pub const Input = struct {
    id: []const u8,
    kind: Kind,
    version: []const u8,
    origin: []const u8,
    sha256: []const u8,
    bytes: u64,
    target: ?program.profile.Target = null,
    dependencies: []const []const u8 = &.{},
};
pub const Lock = struct { schema: u32 = 1, inputs: []const Input };

pub fn validate(value: Lock) Error!void {
    if (value.schema != 1) return error.LockUnsupported;
    const limits: contracts.Limits = .{};
    if (value.inputs.len > limits.program_items) return error.ProgramLimit;
    for (value.inputs, 0..) |input, index| {
        try program.validation.identifier(input.id);
        if (program.find(Input, value.inputs[0..index], input.id) != null)
            return error.ProgramDuplicate;
        try text(input.version, 128);
        try text(input.origin, limits.path_bytes);
        try digest(input.sha256);
        if (input.bytes > limits.http_body_bytes) return error.ProgramLimit;
        if (input.kind == .runtime and input.target == null) return error.LockMismatch;
        if (input.dependencies.len > limits.program_items) return error.ProgramLimit;
        for (input.dependencies, 0..) |id, offset| {
            if (program.find(Input, value.inputs, id) == null) return error.LockMissing;
            for (input.dependencies[0..offset]) |previous| {
                if (std.mem.eql(u8, id, previous)) return error.ProgramDuplicate;
            }
        }
    }
    try acyclic(value.inputs);
}

fn text(value: []const u8, maximum: usize) Error!void {
    if (value.len == 0 or value.len > maximum) return error.ProgramLimit;
    if (!std.unicode.utf8ValidateSlice(value) or std.mem.indexOfScalar(u8, value, 0) != null)
        return error.ProgramInvalid;
}

pub fn digest(value: []const u8) Error!void {
    if (contracts.ids.parseHex32(value) == null) return error.ProgramDigest;
}

fn acyclic(inputs: []const Input) Error!void {
    var ready: [contracts.limits.default.program_items]bool = @splat(false);
    var remaining = inputs.len;
    for (0..inputs.len) |_| {
        var progressed = false;
        for (inputs, 0..) |input, index| {
            if (ready[index]) continue;
            var complete = true;
            for (input.dependencies) |id| {
                for (inputs, 0..) |candidate, position| {
                    if (std.mem.eql(u8, candidate.id, id) and !ready[position]) complete = false;
                }
            }
            if (complete) {
                ready[index] = true;
                remaining -= 1;
                progressed = true;
            }
        }
        if (remaining == 0) return;
        if (!progressed) return error.LockCycle;
    }
}

pub fn normalize(arena: std.mem.Allocator, value: Lock) Error!Lock {
    try validate(value);
    const inputs = try arena.dupe(Input, value.inputs);
    std.mem.sort(Input, inputs, {}, struct {
        fn less(_: void, a: Input, b: Input) bool {
            return std.mem.lessThan(u8, a.id, b.id);
        }
    }.less);
    for (inputs) |*input| {
        const dependencies = try arena.dupe([]const u8, input.dependencies);
        std.mem.sort([]const u8, dependencies, {}, struct {
            fn less(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.less);
        input.dependencies = dependencies;
    }
    return .{ .inputs = inputs };
}

pub fn encode(arena: std.mem.Allocator, value: Lock) Error![]const u8 {
    const bytes = try std.json.Stringify.valueAlloc(arena, try normalize(arena, value), .{});
    if (bytes.len > (contracts.Limits{}).manifest_bytes) return error.ProgramLimit;
    return bytes;
}

pub fn decode(arena: std.mem.Allocator, bytes: []const u8) Error!Lock {
    const value = try contracts.json.decode(Lock, arena, bytes, .{
        .max_bytes = (contracts.Limits{}).manifest_bytes,
        .max_schema = 1,
    });
    try validate(value);
    return value;
}

pub fn verify(input: Input, bytes: []const u8) Error!void {
    const expected = contracts.ids.parseHex32(input.sha256) orelse return error.ProgramDigest;
    if (input.bytes > (contracts.Limits{}).http_body_bytes) return error.ProgramLimit;
    if (input.bytes != bytes.len) return error.LockMismatch;
    var hash: [32]u8 = undefined; // SAFETY: SHA-256 fills the complete digest.
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    if (!std.mem.eql(u8, &hash, &expected)) return error.LockMismatch;
}

test "N2-COMPILER-01: dependency identities reject missing, cyclic and changed inputs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var items = [_]Input{
        .{
            .id = "a",
            .kind = .content,
            .version = "1",
            .origin = "a",
            .sha256 = try program.digest(a, "hello"),
            .bytes = 5,
            .dependencies = &.{"b"},
        },
        .{
            .id = "b",
            .kind = .content,
            .version = "1",
            .origin = "b",
            .sha256 = try program.digest(a, ""),
            .bytes = 0,
        },
    };
    try validate(.{ .inputs = &items });
    try verify(items[0], "hello");
    try std.testing.expectError(error.LockMismatch, verify(items[0], "other"));
    items[1].dependencies = &.{"a"};
    try std.testing.expectError(error.LockCycle, validate(.{ .inputs = &items }));
    items[1].dependencies = &.{"missing"};
    try std.testing.expectError(error.LockMissing, validate(.{ .inputs = &items }));
}

test "N2-COMPILER-01: lock normalization is independent of input order" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first: Input = .{
        .id = "a",
        .kind = .content,
        .version = "1",
        .origin = "a",
        .sha256 = try program.digest(a, ""),
        .bytes = 0,
    };
    var second = first;
    second.id = "b";
    const left = try encode(a, .{ .inputs = &.{ first, second } });
    const right = try encode(a, .{ .inputs = &.{ second, first } });
    try std.testing.expectEqualStrings(left, right);
    try std.testing.expectEqualStrings(left, try encode(a, try decode(a, left)));
}
