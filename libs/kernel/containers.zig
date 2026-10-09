//! Hash-verified private container storage and frozen inventories, independent of guest code.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const content = @import("content");
const access = @import("access");
const platform = @import("platform");
const t = @import("types.zig");
const storage = @import("storage.zig");
const wire = @import("wire.zig");
const evaluation = @import("evaluation.zig");
const Error = t.Error;
const limits = contracts.limits.default;
pub const Item = struct { resource: t.Resource, body: content.Body };
pub const Inventory = struct {
    roots: []const Root,
    files: []const std.Io.File,
    pub const Root = struct { id: []const u8, items: []const Item };

    pub fn close(self: Inventory, io: std.Io) void {
        for (self.files) |file| file.close(io);
    }

    pub fn root(self: Inventory, id: []const u8) Error!Root {
        for (self.roots) |value| if (std.mem.eql(u8, value.id, id)) return value;
        return error.KernelInvalid;
    }
};

/// Validate source bytes, logical resources and aggregate grants before creating CAS entries.
pub fn preflight(
    store: storage.Store,
    desired: []const t.DesiredContainer,
    provider: t.ContentProvider,
    model: program.model.Product,
) Error!void {
    if (desired.len > limits.program_items) return error.KernelLimit;
    for (desired) |proposal| {
        const grant = try evaluation.authorize(model, proposal);
        std.debug.assert(grant.max_entries > 0);
    }
    var usage: std.StringHashMapUnmanaged(Usage) = .empty;
    var entry_count: usize = 0;
    var output_bytes: u64 = 0;
    for (model.roots) |root| {
        var items: std.ArrayList(Item) = .empty;
        for (desired) |proposal| {
            if (!std.mem.eql(u8, root.id, proposal.root)) continue;
            const source = try preflightSource(store, proposal.container, provider);
            defer if (source.file) |file| file.close(store.io);
            const actual = try hashBody(store.io, source.body);
            if (!std.mem.eql(u8, &actual, &proposal.container.sha256))
                return error.ProgramDigest;
            const tree = try content.parseTar(store.arena, store.io, try slice(source.body), .{});
            const grant = try budget(store.arena, &usage, model, proposal, tree);
            for (tree.entries) |entry| {
                output_bytes = std.math.add(u64, output_bytes, entry.body.length) catch
                    return error.KernelLimit;
                if (output_bytes > limits.expanded_bytes) return error.KernelLimit;
            }
            try appendTree(store, &items, proposal, tree, grant.prefix);
        }
        std.mem.sort(Item, items.items, {}, struct {
            fn less(_: void, left: Item, right: Item) bool {
                return std.mem.lessThan(u8, left.resource.path, right.resource.path);
            }
        }.less);
        try conflicts(store.arena, items.items);
        entry_count = std.math.add(usize, entry_count, items.items.len) catch
            return error.KernelLimit;
        if (entry_count > limits.files_per_artifact) return error.KernelLimit;
    }
}

const PreflightSource = struct { body: content.Body, file: ?std.Io.File = null };

fn preflightSource(
    store: storage.Store,
    reference: content.ContainerRef,
    provider: t.ContentProvider,
) Error!PreflightSource {
    if (reference.bytes > limits.expanded_bytes) return error.KernelLimit;
    const path = try casPath(store.arena, reference);
    if (try store.exists(path)) {
        const file = try store.openFile(path);
        errdefer file.close(store.io);
        const size = file.length(store.io) catch |err| return platform.api.mapFs(err);
        if (size != reference.bytes) return error.ProgramDigest;
        return .{ .file = file, .body = .{
            .source = .{ .file = .{ .handle = file, .length = size } },
            .length = size,
        } };
    }
    const callback = provider.open orelse return error.KernelEvaluation;
    const body = try callback(provider.context, store.arena, store.io, reference);
    if (body.length != reference.bytes) return error.ProgramDigest;
    return .{ .body = body };
}

fn slice(body: content.Body) Error!content.Source {
    if (body.offset > body.source.size() or body.length > body.source.size() - body.offset)
        return error.KernelLimit;
    return switch (body.source) {
        .bytes => |bytes| blk: {
            const start = std.math.cast(usize, body.offset) orelse return error.KernelLimit;
            const count = std.math.cast(usize, body.length) orelse return error.KernelLimit;
            break :blk .{ .bytes = bytes[start..][0..count] };
        },
        .file => |file| .{ .file = .{
            .handle = file.handle,
            .offset = std.math.add(u64, file.offset, body.offset) catch
                return error.KernelLimit,
            .length = body.length,
            .cancel = file.cancel,
        } },
    };
}

pub fn freeze(
    store: storage.Store,
    desired: []const t.DesiredContainer,
    provider: t.ContentProvider,
) Error!void {
    for (desired) |item| {
        if (item.container.bytes > limits.expanded_bytes) return error.KernelLimit;
        const path = try casPath(store.arena, item.container);
        if (try store.exists(path)) {
            const file = try store.openFile(path);
            defer file.close(store.io);
            try verify(store.io, file, item.container);
            continue;
        }
        const callback = provider.open orelse return error.KernelEvaluation;
        const body = try callback(provider.context, store.arena, store.io, item.container);
        if (body.length != item.container.bytes) return error.ProgramDigest;
        const parent = try store.openParent(path, true);
        defer parent.close(store.io);
        const temp = try store.arena.print(
            "incoming-{s}",
            .{
                try storage.nonce(
                    store.arena,
                    store.io,
                ),
            },
        );
        defer parent.dir.deleteFile(store.io, temp) catch |err| switch (err) {
            error.FileNotFound => {},
            else => std.log.warn("content staging cleanup: {s}", .{@errorName(err)}),
        };
        const created = try access.createFile(store.arena, store.io, parent.dir, temp);
        defer created.file.close(store.io);
        const digest = try copy(store.io, body, created.file);
        if (!std.mem.eql(u8, &digest, &item.container.sha256)) return error.ProgramDigest;
        created.file.sync(store.io) catch |err| return platform.api.mapFs(err);
        std.Io.Dir.rename(parent.dir, temp, parent.dir, parent.name, store.io) catch |err|
            return platform.api.mapFs(err);
        try storage.sync(store.io, parent.dir);
    }
}

pub fn casPath(arena: std.mem.Allocator, reference: content.ContainerRef) Error![]const u8 {
    return arena.print(
        storage.metadata ++ "/cas/{s}.tar",
        .{
            std.fmt.bytesToHex(reference.sha256, .lower),
        },
    );
}

pub fn verify(io: std.Io, file: std.Io.File, reference: content.ContainerRef) Error!void {
    const length = file.length(io) catch |err| return platform.api.mapFs(err);
    if (length != reference.bytes) return error.ProgramDigest;
    const digest = try hashBody(
        io,
        .{
            .source = .{ .file = .{ .handle = file, .length = length } },
            .length = length,
        },
    );
    if (!std.mem.eql(u8, &digest, &reference.sha256)) return error.ProgramDigest;
}

pub fn hashBody(io: std.Io, body: content.Body) Error!contracts.Digest {
    return transfer(io, body, null);
}

pub fn copy(io: std.Io, body: content.Body, file: std.Io.File) Error!contracts.Digest {
    return transfer(io, body, file);
}

fn transfer(io: std.Io, body: content.Body, file: ?std.Io.File) Error!contracts.Digest {
    if (body.length > limits.expanded_bytes or body.offset > body.source.size() or
        body.length > body.source.size() - body.offset) return error.KernelLimit;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var bytes: [64 << 10]u8 = undefined; // SAFETY: source.read fills each consumed slice.
    var offset: u64 = 0;
    while (offset < body.length) {
        const count = std.math.cast(usize, @min(bytes.len, body.length - offset)) orelse
            return error.KernelLimit;
        try body.source.read(io, body.offset + offset, bytes[0..count]);
        if (file) |output| {
            output.writeStreamingAll(
                io,
                bytes[0..count],
            ) catch |err| return platform.api.mapFs(
                err,
            );
        }
        hash.update(bytes[0..count]);
        offset += count;
    }
    return hash.finalResult();
}

pub fn inventory(
    store: storage.Store,
    roots: []const t.RootBinding,
    desired: []const t.DesiredContainer,
    model: program.model.Product,
) Error!Inventory {
    const result = try store.arena.alloc(Inventory.Root, roots.len);
    var files: std.ArrayList(std.Io.File) = .empty;
    var usage: std.StringHashMapUnmanaged(Usage) = .empty;
    var entry_count: usize = 0;
    var output_bytes: u64 = 0;
    errdefer for (files.items) |file| file.close(store.io);
    for (roots, 0..) |root, index| {
        var items: std.ArrayList(Item) = .empty;
        for (desired) |proposal| {
            if (!std.mem.eql(u8, root.id, proposal.root)) continue;
            const file = try store.openFile(try casPath(store.arena, proposal.container));
            try files.append(store.arena, file);
            try verify(store.io, file, proposal.container);
            const tree = try content.parseTar(
                store.arena,
                store.io,
                .{
                    .file = .{
                        .handle = file,
                        .length = proposal.container.bytes,
                    },
                },
                .{},
            );
            const grant = try budget(store.arena, &usage, model, proposal, tree);
            for (tree.entries) |entry| {
                output_bytes = std.math.add(u64, output_bytes, entry.body.length) catch
                    return error.KernelLimit;
                if (output_bytes > limits.expanded_bytes) return error.KernelLimit;
            }
            try appendTree(store, &items, proposal, tree, grant.prefix);
        }
        std.mem.sort(
            Item,
            items.items,
            {},
            struct {
                fn less(_: void, left: Item, right: Item) bool {
                    return std.mem.lessThan(u8, left.resource.path, right.resource.path);
                }
            }.less,
        );
        try conflicts(store.arena, items.items);
        entry_count = std.math.add(
            usize,
            entry_count,
            items.items.len,
        ) catch return error.KernelLimit;
        if (entry_count > limits.files_per_artifact) return error.KernelLimit;
        result[index] = .{ .id = root.id, .items = items.items };
    }
    return .{ .roots = result, .files = files.items };
}

const Usage = struct {
    entries: usize = 0,
    bytes: u64 = 0,
    paths: std.StringHashMapUnmanaged(content.Kind) = .empty,
};

fn budget(
    arena: std.mem.Allocator,
    usage: *std.StringHashMapUnmanaged(Usage),
    model: program.model.Product,
    proposal: t.DesiredContainer,
    tree: content.Tree,
) Error!program.model.Grant {
    const grant = try evaluation.authorize(model, proposal);
    const current = try usage.getOrPut(arena, grant.id);
    if (!current.found_existing) current.value_ptr.* = .{};
    const value = current.value_ptr;
    for (tree.entries) |entry| {
        const path = if (proposal.prefix.len == 0) entry.path else try arena.print(
            "{s}/{s}",
            .{ proposal.prefix, entry.path },
        );
        try wire.path(path);
        try chargePath(arena, value, grant.max_entries, path, entry.kind);
        var parent = std.fs.path.dirnamePosix(path);
        for (0..limits.path_components) |_| {
            const name = parent orelse break;
            try chargePath(arena, value, grant.max_entries, name, .directory);
            parent = std.fs.path.dirnamePosix(name);
        }
        if (parent != null) return error.KernelLimit;
        value.bytes = std.math.add(
            u64,
            value.bytes,
            entry.body.length,
        ) catch return error.KernelLimit;
        if (value.bytes > grant.max_bytes) return error.KernelLimit;
    }
    return grant;
}

fn chargePath(
    arena: std.mem.Allocator,
    usage: *Usage,
    maximum: u32,
    path: []const u8,
    kind: content.Kind,
) Error!void {
    std.debug.assert(maximum > 0);
    const entry = try usage.paths.getOrPut(arena, path);
    if (entry.found_existing) {
        if (kind != .directory or entry.value_ptr.* != .directory) return error.KernelConflict;
        return;
    }
    entry.value_ptr.* = kind;
    usage.entries += 1;
    if (usage.entries > maximum) return error.KernelLimit;
}

fn appendTree(
    store: storage.Store,
    items: *std.ArrayList(Item),
    proposal: t.DesiredContainer,
    tree: content.Tree,
    grant_prefix: []const u8,
) Error!void {
    var links: ?content.names.LinkResolver = null;
    for (tree.entries) |entry| {
        const path = if (proposal.prefix.len == 0) entry.path else try store.arena.print(
            "{s}/{s}",
            .{
                proposal.prefix, entry.path,
            },
        );
        try wire.path(path);
        const link_directory = try linkDirectory(store.arena, tree, entry, &links);
        if (entry.kind == .directory and try existingDirectory(
            items.items,
            path,
            proposal.directory_access,
        )) continue;
        if (items.items.len >= limits.files_per_artifact) return error.KernelLimit;
        try items.append(
            store.arena,
            .{
                .resource = .{
                    .path = path,
                    .kind = entry.kind,
                    .sha256 = try hashBody(store.io, entry.body),
                    .bytes = entry.body.length,
                    .link_target = entry.link_target,
                    .link_directory = link_directory,
                    .policy = if (entry.kind == .directory)
                        proposal.directory_access
                    else
                        proposal.file_access,
                },
                .body = entry.body,
            },
        );
        try parents(store.arena, items, path, proposal.directory_access, grant_prefix);
    }
}

fn linkDirectory(
    arena: std.mem.Allocator,
    tree: content.Tree,
    entry: content.Entry,
    resolver: *?content.names.LinkResolver,
) Error!bool {
    if (entry.kind != .symlink) return false;
    try wire.linkTarget(entry.link_target);
    if (resolver.* == null) resolver.* = try content.names.LinkResolver.init(arena, tree, limits);
    const target = try resolver.*.?.resolve(entry.path);
    if (target.path.len > 0) try wire.path(target.path);
    if (target.kind) |kind| return kind == .directory;
    if (@import("builtin").os.tag == .windows) return error.KernelUnsupported;
    return false;
}

fn existingDirectory(items: []const Item, path: []const u8, requested: access.Policy) Error!bool {
    for (items) |item| {
        if (!std.mem.eql(u8, item.resource.path, path)) continue;
        if (item.resource.kind != .directory or
            !@import("access_policy").equal(item.resource.policy, requested))
        {
            return error.KernelConflict;
        }
        return true;
    }
    return false;
}

fn parents(
    arena: std.mem.Allocator,
    items: *std.ArrayList(Item),
    path: []const u8,
    policy: access.Policy,
    grant_prefix: []const u8,
) Error!void {
    var parent = std.fs.path.dirnamePosix(path);
    for (0..limits.path_components) |_| {
        const value = parent orelse return;
        const requested = if (evaluation.within(grant_prefix, value))
            policy
        else
            access.privatePolicy(.directory);
        var found = false;
        for (items.items) |item| if (std.mem.eql(u8, item.resource.path, value)) {
            if (item.resource.kind != .directory or !@import("access_policy").equal(
                item.resource.policy,
                requested,
            )) return error.KernelConflict;
            found = true;
        };
        if (!found) {
            if (items.items.len >= limits.files_per_artifact) return error.KernelLimit;
            try items.append(
                arena,
                .{
                    .resource = .{
                        .path = value,
                        .kind = .directory,
                        .sha256 = emptyHash(),
                        .bytes = 0,
                        .policy = requested,
                    },
                    .body = .{},
                },
            );
        }
        parent = std.fs.path.dirnamePosix(value);
    }
    return error.KernelLimit;
}

fn conflicts(arena: std.mem.Allocator, items: []const Item) Error!void {
    var names: std.StringHashMapUnmanaged(content.Kind) = .empty;
    for (items) |item| {
        const key = item.resource.path;
        const entry = try names.getOrPut(arena, key);
        if (entry.found_existing) return error.KernelConflict;
        entry.value_ptr.* = item.resource.kind;
        var parent = std.fs.path.dirnamePosix(key);
        for (0..limits.path_components) |_| {
            const value = parent orelse break;
            if (names.get(value)) |kind| if (kind != .directory) return error.KernelConflict;
            parent = std.fs.path.dirnamePosix(value);
        }
    }
}

fn emptyHash() contracts.Digest {
    var digest: contracts.Digest = undefined; // SAFETY: hash writes every byte.
    std.crypto.hash.sha2.Sha256.hash("", &digest, .{});
    return digest;
}

pub fn states(
    arena: std.mem.Allocator,
    value: Inventory,
    transaction: []const u8,
) Error![]const t.RootState {
    const roots = try arena.alloc(t.RootState, value.roots.len);
    for (value.roots, 0..) |root, index| {
        const resources = try arena.alloc(t.Resource, root.items.len);
        for (root.items, 0..) |item, i| resources[i] = item.resource;
        try wire.resources(resources);
        roots[index] = .{ .id = root.id, .generation = transaction, .resources = resources };
    }
    return roots;
}
