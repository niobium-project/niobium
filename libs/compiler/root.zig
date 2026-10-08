//! Build-time product authoring. Every frontend uses this typed, bounded builder.

const std = @import("std");
const contracts = @import("contracts");
pub const program = @import("program");
const wasm_profile = @import("wasm_profile");

pub const Error = program.Error || wasm_profile.Error || error{
    AuthoringLimit,
    UnknownInstance,
};

pub const Binding = enum { input, asset, resource };

pub const Builder = struct {
    arena: std.mem.Allocator,
    model: program.Program,
    inputs: std.ArrayList(program.Input) = .empty,
    libraries: std.ArrayList(program.Library) = .empty,
    assets: std.ArrayList(program.Asset) = .empty,
    resources: std.ArrayList(program.Resource) = .empty,
    instances: std.ArrayList(program.Instance) = .empty,
    upgrades: std.ArrayList(program.Migration) = .empty,
    copied_bytes: usize = 0,

    pub fn init(
        arena: std.mem.Allocator,
        product_id: []const u8,
        release_sequence: u64,
        model_version: u32,
    ) Error!Builder {
        var builder: Builder = .{
            .arena = arena,
            .model = .{
                .schema = 1,
                .runtime_abi = 1,
                .product_id = "",
                .release_sequence = release_sequence,
                .model_version = model_version,
                .inputs = &.{},
                .libraries = &.{},
                .assets = &.{},
                .resources = &.{},
                .instances = &.{},
                .upgrades = &.{},
            },
        };
        builder.model.product_id = try builder.copy(product_id);
        return builder;
    }

    fn copy(self: *Builder, bytes: []const u8) Error![]const u8 {
        const limit = (contracts.Limits{}).program_bytes;
        std.debug.assert(self.copied_bytes <= limit);
        if (bytes.len > limit - self.copied_bytes) return error.AuthoringLimit;
        const result = try self.arena.dupe(u8, bytes);
        self.copied_bytes += bytes.len;
        return result;
    }

    fn room(count: usize) Error!void {
        if (count >= (contracts.Limits{}).program_items) return error.AuthoringLimit;
    }

    pub fn addInput(self: *Builder, id: []const u8, default: []const u8) Error!void {
        try room(self.inputs.items.len);
        try self.inputs.append(self.arena, .{
            .id = try self.copy(id),
            .default = try self.copy(default),
        });
    }

    pub fn addLibrary(self: *Builder, id: []const u8, wasm: []const u8) Error!void {
        try room(self.libraries.items.len);
        try wasm_profile.validate(wasm, .{});
        const bytes = try self.copy(wasm);
        try self.libraries.append(self.arena, .{
            .id = try self.copy(id),
            .abi = 1,
            .sha256 = try program.digest(self.arena, bytes),
            .wasm_hex = try program.encodeHex(self.arena, bytes),
        });
    }

    pub fn addAsset(self: *Builder, id: []const u8, bytes: []const u8) Error!void {
        try room(self.assets.items.len);
        const owned = try self.copy(bytes);
        try self.assets.append(self.arena, .{
            .id = try self.copy(id),
            .sha256 = try program.digest(self.arena, owned),
            .data_hex = try program.encodeHex(self.arena, owned),
        });
    }

    pub fn addResource(self: *Builder, id: []const u8, path: []const u8) Error!void {
        try room(self.resources.items.len);
        try self.resources.append(self.arena, .{
            .id = try self.copy(id),
            .path = try self.copy(path),
        });
    }

    pub fn addInstance(
        self: *Builder,
        id: []const u8,
        library: []const u8,
        state_version: u32,
    ) Error!void {
        try room(self.instances.items.len);
        try self.instances.append(self.arena, .{
            .id = try self.copy(id),
            .library = try self.copy(library),
            .state_version = state_version,
            .inputs = &.{},
            .assets = &.{},
            .resources = &.{},
            .migrations = &.{},
        });
    }

    fn instance(self: *Builder, id: []const u8) Error!*program.Instance {
        std.debug.assert(self.instances.items.len <= (contracts.Limits{}).program_items);
        for (self.instances.items) |*item| {
            if (std.mem.eql(u8, item.id, id)) return item;
        }
        return error.UnknownInstance;
    }

    pub fn bind(
        self: *Builder,
        instance_id: []const u8,
        kind: Binding,
        reference: []const u8,
    ) Error!void {
        const item = try self.instance(instance_id);
        const list = switch (kind) {
            .input => &item.inputs,
            .asset => &item.assets,
            .resource => &item.resources,
        };
        try room(list.len);
        const next = try self.arena.alloc([]const u8, list.len + 1);
        @memcpy(next[0..list.len], list.*);
        next[list.len] = try self.copy(reference);
        list.* = next;
    }

    /// Empty owner means a product-model migration; otherwise it names a library instance.
    pub fn addMigration(
        self: *Builder,
        owner: []const u8,
        id: []const u8,
        from: u32,
        to: u32,
    ) Error!void {
        const migration: program.Migration = .{ .id = try self.copy(id), .from = from, .to = to };
        if (owner.len == 0) {
            try room(self.upgrades.items.len);
            return self.upgrades.append(self.arena, migration);
        }
        const item = try self.instance(owner);
        try room(item.migrations.len);
        const next = try self.arena.alloc(program.Migration, item.migrations.len + 1);
        @memcpy(next[0..item.migrations.len], item.migrations);
        next[item.migrations.len] = migration;
        item.migrations = next;
    }

    pub fn normalized(self: *const Builder) Error!program.Program {
        var model = self.model;
        model.inputs = self.inputs.items;
        model.libraries = self.libraries.items;
        model.assets = self.assets.items;
        model.resources = self.resources.items;
        model.instances = self.instances.items;
        model.upgrades = self.upgrades.items;
        return program.normalize(self.arena, model);
    }

    pub fn emit(self: *const Builder) Error![]const u8 {
        return program.encode(self.arena, try self.normalized());
    }
};

/// Validate generated IR and every embedded capability before assembling the setup image.
pub fn compile(arena: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    const model = try program.decode(arena, bytes);
    for (model.libraries) |library| {
        try wasm_profile.validate(try program.decodeHex(arena, library.wasm_hex), .{});
    }
    return program.encode(arena, try program.normalize(arena, model));
}

test "N2-AUTH-01: authoring owns input bytes and bounds additions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var builder = try Builder.init(arena.allocator(), "example.product", 1, 1);
    var value = [_]u8{ 'o', 'l', 'd' };
    try builder.addInput("choice", &value);
    value[0] = 'n';
    try std.testing.expectEqualStrings("old", builder.inputs.items[0].default);
    try std.testing.expectError(error.UnknownInstance, builder.bind("missing", .input, "choice"));
    for (1..(contracts.Limits{}).program_items) |_| try builder.addInput("bounded", "");
    try std.testing.expectError(error.AuthoringLimit, builder.addInput("overflow", ""));
}

test "N2-AUTH-01: native authoring rejects invalid UTF-8 and preserves Unicode inputs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{ "\xff", "\xc3", "\xc0\xaf", "\xed\xa0\x80" }) |invalid| {
        var builder = try Builder.init(arena.allocator(), "example.product", 1, 1);
        try builder.addInput("choice", invalid);
        try std.testing.expectError(error.ProgramInvalid, builder.emit());
    }
    const unicode = "caf\u{e9} \u{1f680}";
    var builder = try Builder.init(arena.allocator(), "example.product", 1, 1);
    try builder.addInput("choice", unicode);
    const emitted = try builder.emit();
    const decoded = try program.decode(arena.allocator(), emitted);
    try std.testing.expectEqualStrings(unicode, decoded.inputs[0].default);
    try std.testing.expectEqualStrings(emitted, try program.encode(arena.allocator(), decoded));
}
