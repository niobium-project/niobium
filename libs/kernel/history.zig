//! Durable migration identities are immutable even after a call clears its private state.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const t = @import("types.zig");
const wire = @import("wire.zig");

pub fn validate(arena: std.mem.Allocator, snapshot: t.Snapshot) t.Error!void {
    const limit = contracts.limits.default.plan_ops;
    std.debug.assert(limit > 0);
    if (snapshot.migrations.len > limit or snapshot.model_migrations.len > limit) {
        return error.KernelLimit;
    }
    var identities: std.StringHashMapUnmanaged([]const u8) = .empty;
    for (snapshot.migrations) |migration| {
        try wire.migrationValid(migration);
        const key = try arena.print("{s}/{s}", .{ migration.call, migration.rule.id });
        const digest = try program.digest(arena, try wire.encode(arena, migration.rule));
        const item = try identities.getOrPut(arena, key);
        if (item.found_existing and !std.mem.eql(u8, item.value_ptr.*, digest)) {
            return error.KernelState;
        }
        item.value_ptr.* = digest;
    }
    var model_ids: std.StringHashMapUnmanaged(void) = .empty;
    var previous: ?u32 = null;
    for (snapshot.model_migrations) |migration| {
        try program.validation.identifier(migration.id);
        if (migration.from == 0 or migration.from >= migration.to) return error.KernelState;
        if (previous) |version| if (migration.from != version) return error.KernelState;
        const item = try model_ids.getOrPut(arena, migration.id);
        if (item.found_existing) return error.KernelState;
        previous = migration.to;
    }
    if (previous) |version| if (version != snapshot.model_version) return error.KernelState;
}

/// Declarations may retire old converters, but may not redefine an already applied ID.
pub fn declared(
    arena: std.mem.Allocator,
    product: program.model.Product,
    snapshot: t.Snapshot,
) t.Error!void {
    var applied: std.StringHashMapUnmanaged(program.model.Migration) = .empty;
    for (snapshot.migrations) |migration| {
        const key = try arena.print("{s}/{s}", .{ migration.call, migration.rule.id });
        try applied.put(arena, key, migration.rule);
    }
    for (product.calls) |call| {
        for (call.migrations) |rule| {
            const key = try arena.print("{s}/{s}", .{ call.id, rule.id });
            const previous = applied.get(key) orelse continue;
            if (!sameRule(previous, rule)) return error.KernelUpgrade;
        }
    }
    var models: std.StringHashMapUnmanaged(program.Migration) = .empty;
    for (snapshot.model_migrations) |rule| try models.put(arena, rule.id, rule);
    for (product.upgrades) |rule| {
        const previous = models.get(rule.id) orelse continue;
        if (previous.from != rule.from or previous.to != rule.to) return error.KernelUpgrade;
    }
}

fn sameRule(a: program.model.Migration, b: program.model.Migration) bool {
    if (a.from != b.from or a.to != b.to) return false;
    inline for (.{ "id", "library", "interface", "function", "implementation_sha256" }) |field| {
        if (!std.mem.eql(u8, @field(a, field), @field(b, field))) return false;
    }
    return true;
}
