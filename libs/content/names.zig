//! UTF-8 logical names. Target filesystem restrictions belong to deployment validation.

const std = @import("std");
const contracts = @import("contracts");
const content = @import("root.zig");

pub fn check(name: []const u8, limits: contracts.Limits) content.Error!void {
    std.debug.assert(limits.path_components > 0);
    if (name.len == 0 or name.len > limits.path_bytes) return error.ContentInvalid;
    if (!std.unicode.utf8ValidateSlice(name)) return error.ContentInvalid;
    if (std.mem.findScalar(u8, name, 0) != null) return error.ContentInvalid;
    var parts = std.mem.splitScalar(u8, name, '/');
    var count: u32 = 0;
    while (parts.next()) |part| {
        count += 1;
        if (count > limits.path_components) return error.ContentLimit;
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) {
            return error.ContentInvalid;
        }
    }
}

pub fn sourceName(
    raw: []const u8,
    directory: bool,
    limits: contracts.Limits,
) content.Error![]const u8 {
    std.debug.assert(limits.path_bytes > 0);
    if (raw.len > limits.path_bytes) return error.ContentLimit;
    if (raw.len > 0 and raw[0] == '/') return error.ContentInvalid;
    var name = raw;
    while (std.mem.startsWith(u8, name, "./")) name = name[2..];
    if (directory and std.mem.endsWith(u8, name, "/")) name = name[0 .. name.len - 1];
    if (directory and (name.len == 0 or std.mem.eql(u8, name, "."))) return "";
    try check(name, limits);
    return name;
}

pub fn resolveLink(
    arena: std.mem.Allocator,
    path: []const u8,
    target: []const u8,
    limits: contracts.Limits,
) content.Error![]const u8 {
    std.debug.assert(path.len > 0);
    if (target.len == 0 or target.len > limits.path_bytes) return error.ContentInvalid;
    if (target[0] == '/' or !std.unicode.utf8ValidateSlice(target)) return error.ContentInvalid;
    if (std.mem.findScalar(u8, target, 0) != null) return error.ContentInvalid;
    const parent = std.fs.path.dirnamePosix(path) orelse "";
    const joined = try std.mem.concat(arena, u8, &.{ parent, "/", target });
    var result: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, joined, '/');
    var count: u32 = 0;
    while (parts.next()) |part| {
        count += 1;
        if (count > @as(u32, limits.path_components) * 2 + 1) return error.ContentLimit;
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (result.pop() == null) return error.ContentInvalid;
        } else try result.append(arena, part);
    }
    const name = try std.mem.join(arena, "/", result.items);
    if (name.len > 0) try check(name, limits);
    return name;
}

/// Resolve logical links without touching the host filesystem. Bounded expansion rejects cycles.
pub fn checkLinks(
    arena: std.mem.Allocator,
    entries: []const content.Entry,
    seen: *const std.StringHashMapUnmanaged(usize),
    limits: contracts.Limits,
) content.Error!void {
    std.debug.assert(entries.len <= limits.files_per_artifact);
    for (entries) |entry| {
        if (entry.kind != .symlink) continue;
        const resolved = try followLink(arena, entries, seen, entry.path, limits);
        std.debug.assert(resolved.path.len <= limits.path_bytes);
    }
}

pub const ResolvedLink = struct { path: []const u8, kind: ?content.Kind };

/// Index a logical tree once when a deployment backend needs resolved link kinds.
/// The resolution never opens a host path and never changes Entry.link_target.
pub const LinkResolver = struct {
    arena: std.mem.Allocator,
    entries: []const content.Entry,
    seen: std.StringHashMapUnmanaged(usize),
    limits: contracts.Limits,

    pub fn init(
        arena: std.mem.Allocator,
        tree: content.Tree,
        limits: contracts.Limits,
    ) content.Error!LinkResolver {
        if (tree.entries.len > limits.files_per_artifact) return error.ContentLimit;
        var seen: std.StringHashMapUnmanaged(usize) = .empty;
        for (tree.entries, 0..) |entry, index| {
            try check(entry.path, limits);
            if (entry.kind == .symlink) {
                const target = try resolveLink(arena, entry.path, entry.link_target, limits);
                std.debug.assert(target.len <= limits.path_bytes);
            }
            const item = try seen.getOrPut(arena, entry.path);
            if (item.found_existing) return error.ContentConflict;
            item.value_ptr.* = index;
        }
        return .{ .arena = arena, .entries = tree.entries, .seen = seen, .limits = limits };
    }

    pub fn resolve(self: *const LinkResolver, path: []const u8) content.Error!ResolvedLink {
        try check(path, self.limits);
        return followLink(self.arena, self.entries, &self.seen, path, self.limits);
    }
};

fn followLink(
    arena: std.mem.Allocator,
    entries: []const content.Entry,
    seen: *const std.StringHashMapUnmanaged(usize),
    path: []const u8,
    limits: contracts.Limits,
) content.Error!ResolvedLink {
    std.debug.assert(path.len > 0);
    var pending = path;
    var cursor: usize = 0;
    var resolved: std.ArrayList([]const u8) = .empty;
    var hops: u32 = 0;
    while (cursor < pending.len) {
        const end = std.mem.findScalarPos(u8, pending, cursor, '/') orelse pending.len;
        const part = pending[cursor..end];
        cursor = @min(end + 1, pending.len);
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (resolved.pop() == null) return error.ContentInvalid;
            continue;
        }
        try resolved.append(arena, part);
        if (resolved.items.len > limits.path_components) return error.ContentLimit;
        const candidate = try std.mem.join(arena, "/", resolved.items);
        if (candidate.len > limits.path_bytes) return error.ContentLimit;
        const index = seen.get(candidate) orelse continue;
        const entry = entries[index];
        if (entry.kind == .file and cursor < pending.len) return error.ContentInvalid;
        if (entry.kind != .symlink) continue;
        hops += 1;
        if (hops > limits.path_components) return error.ContentInvalid;
        const parent = resolved.pop();
        std.debug.assert(parent != null);
        pending = try std.mem.concat(arena, u8, &.{ entry.link_target, "/", pending[cursor..] });
        if (pending.len > @as(u32, limits.path_bytes) * 2) return error.ContentLimit;
        cursor = 0;
    }
    const name = try std.mem.join(arena, "/", resolved.items);
    const kind: ?content.Kind = if (name.len == 0) .directory else if (seen.get(name)) |index|
        entries[index].kind
    else
        null;
    return .{ .path = name, .kind = kind };
}
