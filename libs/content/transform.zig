//! Metadata transforms preserve borrowed content and reject conflicting destinations.

const std = @import("std");
const contracts = @import("contracts");
const content = @import("root.zig");

pub const Selection = struct {
    /// Keep this path and descendants. Empty selects everything.
    from: []const u8 = "",
    /// Replace the selected prefix. Empty places its contents at the logical root.
    to: []const u8 = "",
};

pub fn normalize(
    arena: std.mem.Allocator,
    entries: []const content.Entry,
    limits: contracts.Limits,
) content.Error!content.Tree {
    std.debug.assert(limits.files_per_artifact > 0);
    if (entries.len > limits.files_per_artifact) return error.ContentLimit;
    var list: std.ArrayList(content.Entry) = .empty;
    var seen: std.StringHashMapUnmanaged(usize) = .empty;
    var total: u64 = 0;
    for (entries) |entry| {
        try validateEntry(entry, limits);
        if (entry.kind == .symlink) {
            const resolved = try content.names.resolveLink(
                arena,
                entry.path,
                entry.link_target,
                limits,
            );
            if (resolved.len > 0) try content.names.check(resolved, limits);
        }
        total = std.math.add(u64, total, entry.body.length) catch return error.ContentLimit;
        if (total > limits.expanded_bytes) return error.ContentLimit;
        var copy = entry;
        copy.path = try arena.dupe(u8, entry.path);
        copy.link_target = try arena.dupe(u8, entry.link_target);
        const slot = try seen.getOrPut(arena, copy.path);
        if (slot.found_existing) return error.ContentConflict;
        slot.value_ptr.* = list.items.len;
        try list.append(arena, copy);
    }
    for (entries) |entry| try parents(arena, &list, &seen, entry.path, limits);
    try content.names.checkLinks(arena, list.items, &seen, limits);
    std.mem.sort(content.Entry, list.items, {}, lessThan);
    return .{ .entries = list.items };
}

fn validateEntry(entry: content.Entry, limits: contracts.Limits) content.Error!void {
    std.debug.assert(limits.path_bytes > 0);
    try content.names.check(entry.path, limits);
    if (entry.mode > 0o777) return error.ContentUnsupported;
    if (entry.body.length > limits.archive_entry_bytes) return error.ContentLimit;
    const end = std.math.add(u64, entry.body.offset, entry.body.length) catch
        return error.ContentInvalid;
    if (end > entry.body.source.size()) return error.ContentInvalid;
    if (entry.kind != .file and entry.body.length != 0) return error.ContentInvalid;
    if (entry.kind != .symlink and entry.link_target.len != 0) return error.ContentInvalid;
}

fn parents(
    arena: std.mem.Allocator,
    list: *std.ArrayList(content.Entry),
    seen: *std.StringHashMapUnmanaged(usize),
    path: []const u8,
    limits: contracts.Limits,
) content.Error!void {
    std.debug.assert(path.len > 0);
    for (path, 0..) |char, index| {
        if (char != '/') continue;
        const parent = path[0..index];
        if (seen.get(parent)) |position| {
            if (list.items[position].kind != .directory) return error.ContentConflict;
            continue;
        }
        if (list.items.len >= limits.files_per_artifact) return error.ContentLimit;
        const name = try arena.dupe(u8, parent);
        try seen.put(arena, name, list.items.len);
        try list.append(arena, .{ .path = name, .kind = .directory, .mode = 0o755 });
    }
}

fn lessThan(_: void, a: content.Entry, b: content.Entry) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

fn within(path: []const u8, prefix: []const u8) bool {
    if (prefix.len == 0) return true;
    if (std.mem.eql(u8, path, prefix)) return true;
    return path.len > prefix.len and std.mem.startsWith(u8, path, prefix) and
        path[prefix.len] == '/';
}

fn remap(
    arena: std.mem.Allocator,
    path: []const u8,
    selection: Selection,
) content.Error![]const u8 {
    std.debug.assert(within(path, selection.from));
    const start = selection.from.len + @intFromBool(selection.from.len > 0 and
        path.len > selection.from.len);
    const suffix = path[start..];
    if (selection.to.len == 0) return arena.dupe(u8, suffix);
    if (suffix.len == 0) return arena.dupe(u8, selection.to);
    return std.mem.concat(arena, u8, &.{ selection.to, "/", suffix });
}

pub fn transform(
    arena: std.mem.Allocator,
    tree: content.Tree,
    selection: Selection,
    limits: contracts.Limits,
) content.Error!content.Tree {
    std.debug.assert(limits.files_per_artifact > 0);
    if (tree.entries.len > limits.files_per_artifact) return error.ContentLimit;
    if (selection.from.len > 0) try content.names.check(selection.from, limits);
    if (selection.to.len > 0) try content.names.check(selection.to, limits);
    var entries: std.ArrayList(content.Entry) = .empty;
    for (tree.entries) |entry| {
        if (!within(entry.path, selection.from)) continue;
        var copy = entry;
        copy.path = try remap(arena, entry.path, selection);
        if (copy.path.len == 0 and copy.kind == .directory) continue;
        try entries.append(arena, copy);
    }
    return normalize(arena, entries.items, limits);
}

/// Equal directories coalesce. Other duplicate paths conflict; provenance stays outside identity.
pub fn merge(
    arena: std.mem.Allocator,
    trees: []const content.Tree,
    limits: contracts.Limits,
) content.Error!content.Tree {
    std.debug.assert(limits.files_per_artifact > 0);
    if (trees.len > limits.files_per_artifact) return error.ContentLimit;
    var entries: std.ArrayList(content.Entry) = .empty;
    var directories: std.StringHashMapUnmanaged(u16) = .empty;
    for (trees) |tree| {
        if (tree.entries.len > limits.files_per_artifact -| entries.items.len) {
            return error.ContentLimit;
        }
        for (tree.entries) |entry| {
            try validateEntry(entry, limits);
            if (entry.kind == .directory) {
                const slot = try directories.getOrPut(arena, entry.path);
                if (slot.found_existing) {
                    if (slot.value_ptr.* != entry.mode) return error.ContentConflict;
                    continue;
                }
                slot.value_ptr.* = entry.mode;
            }
            try entries.append(arena, entry);
        }
    }
    return normalize(arena, entries.items, limits);
}
