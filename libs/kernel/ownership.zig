//! Resolve and authenticate every root before opening a transaction or claiming empty space.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const platform = @import("platform");
const t = @import("types.zig");
const wire = @import("wire.zig");
const storage = @import("storage.zig");
const Error = t.Error;
pub const owner_path = storage.metadata ++ "/owner.json";

pub const Session = struct {
    options: t.Options,
    owner: t.Owner,
    stores: []storage.Store,
    coordinator: usize,

    pub fn close(self: Session) void {
        for (self.stores) |item| item.close();
    }

    pub fn stateStore(self: Session) storage.Store {
        return self.stores[self.coordinator];
    }

    pub fn store(self: Session, id: []const u8) Error!storage.Store {
        for (self.stores) |item| if (std.mem.eql(u8, item.binding.id, id)) return item;
        return error.KernelInvalid;
    }
};

pub fn open(options: t.Options) Error!Session {
    const bindings = try canonical(options);
    try wire.bindings(bindings, options.state_root);
    var ownership: ?t.Owner = null;
    for (bindings) |binding| if (try inspect(options, binding)) |found| {
        if (ownership) |prior| {
            var expected = prior;
            expected.root = binding.id;
            try wire.owner(found, expected);
        } else ownership = found;
    };
    var owner = ownership orelse t.Owner{
        .instance = try storage.nonce(options.arena, options.io),
        .product_id = (options.model orelse return error.KernelOwnership).id,
        .root = options.state_root,
        .state_root = options.state_root,
        .roots = bindings,
    };
    owner.root = options.state_root;
    if (!wire.sameBindings(owner.roots, bindings) or
        !std.mem.eql(u8, owner.state_root, options.state_root)) return error.KernelOwnership;
    if (options.model) |model| {
        if (!std.mem.eql(u8, model.id, owner.product_id)) return error.KernelOwnership;
    }
    if (ownership != null) try durablePreflight(options, owner);
    const stores = try options.arena.alloc(storage.Store, bindings.len);
    var opened: usize = 0;
    errdefer for (stores[0..opened]) |store| store.close();
    var coordinator: usize = 0;
    for (bindings, 0..) |binding, index| {
        stores[index] = try storage.Store.open(options, binding);
        opened += 1;
        if (std.mem.eql(u8, binding.id, options.state_root)) coordinator = index;
        var expected = owner;
        expected.root = binding.id;
        if (try stores[index].read(
            owner_path,
            contracts.limits.default.runtime_plan_bytes,
        )) |bytes| {
            try wire.owner(try wire.decode(t.Owner, options.arena, bytes), expected);
        } else {
            if (!try empty(stores[index].dir, options.io)) return error.KernelOwnership;
            try stores[index].write(owner_path, try wire.encode(options.arena, expected));
        }
    }
    return .{
        .options = options,
        .owner = owner,
        .stores = stores,
        .coordinator = coordinator,
    };
}

fn durablePreflight(options: t.Options, owner: t.Owner) Error!void {
    const binding = program.find(t.RootBinding, owner.roots, owner.state_root) orelse
        return error.KernelOwnership;
    const dir = std.Io.Dir.cwd().openDir(options.io, binding.path, .{
        .follow_symlinks = false,
    }) catch |err| return platform.api.mapFs(err);
    defer dir.close(options.io);
    const view: storage.Store = .{
        .io = options.io,
        .arena = options.arena,
        .binding = binding,
        .dir = dir,
    };
    if (try view.read(
        storage.metadata ++ "/pending.json",
        contracts.limits.default.runtime_plan_bytes,
    )) |bytes| {
        try wire.plan(options.arena, try wire.decode(t.Plan, options.arena, bytes), owner);
    }
    if (try view.read(
        storage.metadata ++ "/installation.json",
        contracts.limits.default.runtime_plan_bytes,
    )) |bytes| {
        const state = try wire.decode(t.Snapshot, options.arena, bytes);
        try wire.snapshot(options.arena, state, owner);
        if (options.model) |model| {
            try @import("input_validation.zig").persisted(model, state.inputs);
            try @import("history.zig").declared(options.arena, model, state);
        }
    }
}

fn canonical(options: t.Options) Error![]const t.RootBinding {
    try wire.bindings(options.roots, options.state_root);
    const result = try options.arena.alloc(t.RootBinding, options.roots.len);
    for (options.roots, 0..) |binding, index| {
        const parent = std.fs.path.dirname(binding.path) orelse return error.KernelInvalid;
        const leaf = std.fs.path.basename(binding.path);
        try wire.path(leaf);
        const resolved = std.Io.Dir.cwd().realPathFileAlloc(
            options.io,
            parent,
            options.arena,
        ) catch |err|
            return platform.api.mapFs(err);
        result[index] = .{
            .id = binding.id,
            .path = try std.fs.path.join(options.arena, &.{ resolved, leaf }),
        };
    }
    std.mem.sort(
        t.RootBinding,
        result,
        {},
        struct {
            fn less(_: void, left: t.RootBinding, right: t.RootBinding) bool {
                return std.mem.lessThan(u8, left.path, right.path);
            }
        }.less,
    );
    return result;
}

fn inspect(options: t.Options, binding: t.RootBinding) Error!?t.Owner {
    const dir = std.Io.Dir.cwd().openDir(
        options.io,
        binding.path,
        .{
            .follow_symlinks = false,
            .iterate = true,
        },
    ) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return platform.api.mapFs(err),
    };
    defer dir.close(options.io);
    const view: storage.Store = .{
        .io = options.io,
        .arena = options.arena,
        .binding = binding,
        .dir = dir,
    };
    if (try view.read(owner_path, contracts.limits.default.runtime_plan_bytes)) |bytes| {
        const value = try wire.decode(t.Owner, options.arena, bytes);
        try wire.owner(value, value);
        if (!std.mem.eql(u8, value.root, binding.id)) return error.KernelOwnership;
        return value;
    }
    if (!try empty(dir, options.io)) return error.KernelOwnership;
    return null;
}

fn empty(dir: std.Io.Dir, io: std.Io) Error!bool {
    var iterator = dir.iterate();
    for (0..2) |_| {
        const entry = iterator.next(io) catch |err| return platform.api.mapFs(err);
        const value = entry orelse return true;
        if (!std.mem.eql(u8, value.name, ".niobium-lock")) return false;
    }
    return false;
}
