//! Native author API for the typed product graph. Construction owns copied input values.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const model = program.model;
const pipeline = @import("pipeline_types.zig");
const source_map = @import("pipeline_source_map.zig");

pub const Error = model.Error || pipeline.Error || error{AuthoringLimit};
pub const Builder = struct {
    arena: std.mem.Allocator,
    product: model.Product,
    copied_bytes: usize = 0,
    scratch: []u8,
    locations: std.ArrayList(pipeline.SourceMap) = .empty,
    source_bytes: usize = 0,

    pub fn init(
        arena: std.mem.Allocator,
        id: []const u8,
        release: u64,
        version: u32,
        profile: program.profile.Profile,
    ) Error!Builder {
        try program.validation.identifier(id);
        try program.profile.validate(profile);
        if (release == 0 or version == 0) return error.ProgramInvalid;
        var builder: Builder = .{
            .arena = arena,
            .scratch = try arena.alloc(u8, contracts.limits.default.program_bytes),
            .product = .{
                .id = "",
                .release_sequence = release,
                .model_version = version,
                .target = profile.target,
                .profile = profile,
            },
        };
        builder.product.id = try builder.snapshot([]const u8, id);
        builder.product.profile = try builder.snapshot(program.profile.Profile, profile);
        return builder;
    }

    /// Borrowed construction objects never escape into an owned builder entry.
    pub fn snapshot(self: *Builder, comptime T: type, value: T) Error!T {
        const limit = contracts.limits.default.program_bytes;
        std.debug.assert(self.copied_bytes <= limit);
        var writer: std.Io.Writer = .fixed(self.scratch[0 .. limit - self.copied_bytes]);
        std.json.Stringify.value(value, .{}, &writer) catch return error.AuthoringLimit;
        const bytes = writer.buffered();
        self.copied_bytes += bytes.len;
        return contracts.json.decode(T, self.arena, bytes, .{
            .max_bytes = limit,
            .limits = .{ .json_depth = model.wire_depth },
        });
    }

    pub fn input(self: *Builder, entry: model.Input) Error!void {
        if (entry.resolved_type != null) return error.ProgramInvalid;
        try program.value.validate(entry.default, .{});
        try self.append("inputs", entry);
    }

    pub fn library(self: *Builder, entry: model.Library) Error!void {
        try self.append("libraries", entry);
    }

    pub fn container(self: *Builder, entry: model.Container) Error!void {
        try self.append("containers", entry);
    }

    pub fn stateRoot(self: *Builder, id: []const u8) Error!void {
        try program.validation.identifier(id);
        self.product.state_root = try self.snapshot([]const u8, id);
    }

    pub fn root(self: *Builder, entry: model.Root) Error!void {
        try self.append("roots", entry);
    }

    pub fn grant(self: *Builder, entry: model.Grant) Error!void {
        try self.append("grants", entry);
    }

    pub fn observe(self: *Builder, entry: model.Observation) Error!void {
        try model.checking.validateObservationShape(entry, .{});
        try self.append("observations", entry);
    }

    pub fn call(self: *Builder, entry: model.Call) Error!void {
        try model.checking.validateCallShape(entry, .{});
        try self.append("calls", entry);
    }

    pub fn upgrade(self: *Builder, entry: program.Migration) Error!void {
        try self.append("upgrades", entry);
    }

    fn append(self: *Builder, comptime field: []const u8, entry: anytype) Error!void {
        try program.validation.identifier(entry.id);
        const previous = @field(self.product, field);
        if (previous.len >= contracts.limits.default.program_items) return error.AuthoringLimit;
        if (program.find(@TypeOf(entry), previous, entry.id) != null) return error.ProgramDuplicate;
        const copy = try self.snapshot(@TypeOf(entry), entry);
        const next = try self.arena.alloc(@TypeOf(entry), previous.len + 1);
        @memcpy(next[0..previous.len], previous);
        next[previous.len] = copy;
        @field(self.product, field) = next;
    }

    /// Source positions are diagnostic-only and have a separate bounded ownership budget.
    pub fn location(self: *Builder, object: []const u8, source: pipeline.Location) Error!void {
        const limit = contracts.limits.default.program_bytes;
        const item: pipeline.SourceMap = .{ .object = object, .source = source };
        try source_map.entry(item);
        const size = object.len + source.file.len;
        if (size > limit - self.source_bytes) return error.AuthoringLimit;
        var existing: ?usize = null;
        for (self.locations.items, 0..) |item_, index| {
            if (std.mem.eql(u8, item_.object, object)) existing = index;
        }
        const count_limit = contracts.limits.default.component_types;
        if (existing == null and self.locations.items.len >= count_limit)
            return error.AuthoringLimit;
        self.source_bytes += size;
        const copied: pipeline.SourceMap = .{
            .object = try self.arena.dupe(u8, object),
            .source = .{
                .file = try self.arena.dupe(u8, source.file),
                .line = source.line,
                .column = source.column,
            },
        };
        if (existing) |index| {
            self.locations.items[index] = copied;
            return;
        }
        try self.locations.append(self.arena, copied);
    }

    pub fn emitSourceMap(self: *const Builder) Error![]const u8 {
        return source_map.encode(self.arena, .{ .locations = self.locations.items });
    }

    pub fn normalized(self: *const Builder) Error!model.Product {
        return model.normalize(self.arena, self.product);
    }

    pub fn emit(self: *const Builder) Error![]const u8 {
        return model.encode(self.arena, self.product);
    }
};

test "N2-AUTH-02: native author input is copied and duplicate construction is atomic" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var builder = try Builder.init(arena.allocator(), "example.product", 1, 1, .{
        .id = "niobium.user",
        .target = .@"x86_64-linux",
        .primitives = &.{},
    });
    var text = [_]u8{ 'o', 'l', 'd' };
    try builder.input(.{ .id = "choice", .default = .{ .text = &text } });
    text[0] = 'n';
    try std.testing.expectEqualStrings("old", builder.product.inputs[0].default.text);
    try std.testing.expectError(error.ProgramDuplicate, builder.input(.{
        .id = "choice",
        .default = .{ .boolean = true },
    }));
    try std.testing.expectEqual(@as(usize, 1), builder.product.inputs.len);
    const encoded = try builder.emit();
    const decoded = try model.decode(arena.allocator(), encoded);
    try std.testing.expectEqualStrings("old", decoded.inputs[0].default.text);
}

test "N2-AUTH-02: source positions do not alter semantic program bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var builder = try Builder.init(arena.allocator(), "example", 1, 1, .{
        .id = "niobium.user",
        .target = .@"aarch64-macos",
        .primitives = &.{},
    });
    const before = try builder.emit();
    try builder.location("product:example", .{ .file = "first.zig", .line = 1, .column = 2 });
    const first = try builder.emitSourceMap();
    try builder.location("product:example", .{ .file = "second.zig", .line = 9, .column = 4 });
    const second = try builder.emitSourceMap();
    try std.testing.expectEqualStrings(before, try builder.emit());
    try std.testing.expect(!std.mem.eql(u8, first, second));
    try std.testing.expectError(
        error.ProgramInvalid,
        builder.location("call:example", .{ .file = "x", .line = 0, .column = 1 }),
    );
}
