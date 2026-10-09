//! Real product programs constructed through the public native author SDK.
const std = @import("std");
const compiler = @import("compiler");
const program = @import("program");
const content = @import("content");
const primitives = @import("host_primitives");
const Value = program.value.Value;
const Binding = program.model.Binding;
pub const Assets = struct {
    files: program.model.Library,
    consumer: program.model.Library,
    primary: content.ContainerRef,
    fallback: content.ContainerRef,
};

pub fn build(
    arena: std.mem.Allocator,
    target: program.profile.Target,
    assets: Assets,
    generated: bool,
    version: u32,
    migration: bool,
) ![]const u8 {
    var author = try compiler.author.Builder.init(
        arena,
        if (generated) "example.toolchain" else "example.files",
        version,
        version,
        primitives.runtimeProfile(target),
    );
    try author.root(.{ .id = "application" });
    try author.stateRoot("application");
    try author.library(assets.files);
    try author.container(
        .{ .id = "primary", .member = "content/primary.tar", .reference = assets.primary },
    );
    try author.container(
        .{ .id = "fallback", .member = "content/fallback.tar", .reference = assets.fallback },
    );
    try author.input(.{ .id = "enabled", .default = .{ .boolean = true } });
    try author.input(.{ .id = "primary", .default = .{ .boolean = true } });
    try author.grant(.{
        .id = "owned",
        .root = "application",
        .primitive = .{ .id = "content.tree", .version = 1 },
        .max_entries = 128,
        .max_bytes = 4 << 20,
        .file_access = .{ .kind = .file, .owner = .fromBits(3), .everyone = .fromBits(1) },
        .directory_access = .{
            .kind = .directory,
            .owner = .fromBits(3),
            .everyone = .fromBits(1),
        },
    });
    try author.call(.{
        .id = "source",
        .library = assets.files.id,
        .interface = "niobium:files/installer@1.0.0",
        .function = "select-content",
        .arguments = &.{
            .{ .literal = try reference(arena, assets.primary) },
            .{ .literal = try reference(arena, assets.fallback) },
            .{ .input = "primary" },
        },
    });
    if (generated) try toolchain(arena, &author, assets, version, migration) else try files(
        arena,
        &author,
        assets,
    );
    if (version == 2 and migration) try author.upgrade(
        .{ .id = "release-1-2", .from = 1, .to = 2 },
    );
    return author.emit();
}

fn toolchain(
    arena: std.mem.Allocator,
    author: *compiler.author.Builder,
    assets: Assets,
    version: u32,
    migration: bool,
) !void {
    try author.library(assets.consumer);
    try author.input(.{ .id = "label", .default = .{ .text = "Toolchain" } });
    try author.observe(
        .{
            .id = "machine",
            .primitive = .{ .id = "machine.facts", .version = 1 },
            .function = "facts",
        },
    );
    const request: Binding = .{ .record = &.{
        .{ .name = "root", .binding = text("application") },
        .{ .name = "grant", .binding = text("owned") },
        .{ .name = "prefix", .binding = text("toolchain") },
        .{ .name = "content", .binding = .{ .node_result = .{ .id = "source" } } },
        .{ .name = "label", .binding = .{ .input = "label" } },
        .{
            .name = "platform",
            .binding = .{ .observation = .{ .id = "machine", .fields = &.{"os"} } },
        },
        .{ .name = "enabled", .binding = .{ .input = "enabled" } },
        .{ .name = "previous", .binding = .previous_state },
    } };
    const rules = if (version == 2 and migration) try arena.dupe(program.model.Migration, &.{.{
        .id = "state-1-2",
        .from = 1,
        .to = 2,
        .library = assets.consumer.id,
        .interface = "niobium:reference/installer@1.0.0",
        .function = "upgrade-state",
        .implementation_sha256 = assets.consumer.sha256,
    }}) else &.{};
    try author.call(.{
        .id = "configure",
        .library = assets.consumer.id,
        .interface = "niobium:reference/installer@1.0.0",
        .function = "build",
        .arguments = &.{request},
        .grants = &.{"owned"},
        .state_version = version,
        .migrations = rules,
        .result_role = .plan,
    });
}

fn files(arena: std.mem.Allocator, author: *compiler.author.Builder, assets: Assets) !void {
    try author.call(.{
        .id = "deploy",
        .library = assets.files.id,
        .interface = "niobium:files/installer@1.0.0",
        .function = "build",
        .grants = &.{"owned"},
        .result_role = .plan,
        .arguments = &.{.{ .record = &.{
            .{ .name = "root", .binding = text("application") },
            .{ .name = "grant", .binding = text("owned") },
            .{ .name = "prefix", .binding = text("sdk") },
            .{ .name = "content", .binding = .{ .node_result = .{ .id = "source" } } },
            .{ .name = "enabled", .binding = .{ .input = "enabled" } },
            .{ .name = "file-access", .binding = .{ .literal = try policy(arena, "file") } },
            .{
                .name = "directory-access",
                .binding = .{ .literal = try policy(arena, "directory") },
            },
        } }},
    });
}

fn text(bytes: []const u8) Binding {
    return .{ .literal = .{ .text = bytes } };
}

fn reference(arena: std.mem.Allocator, ref: content.ContainerRef) !Value {
    return .{ .record = try arena.dupe(program.value.Field, &.{
        .{ .name = "format", .value = .{ .enumeration = "posix-pax-v1" } },
        .{ .name = "sha256", .value = .{ .bytes = try arena.dupe(u8, &ref.sha256) } },
        .{ .name = "bytes", .value = .{ .uint64 = ref.bytes } },
    }) };
}

fn policy(arena: std.mem.Allocator, kind: []const u8) !Value {
    const owner: Value = .{ .record = &.{
        .{ .name = "read", .value = .{ .boolean = true } },
        .{ .name = "write", .value = .{ .boolean = true } },
        .{ .name = "execute", .value = .{ .boolean = false } },
    } };
    const everyone: Value = .{ .record = &.{
        .{ .name = "read", .value = .{ .boolean = true } },
        .{ .name = "write", .value = .{ .boolean = false } },
        .{ .name = "execute", .value = .{ .boolean = false } },
    } };
    return .{ .record = try arena.dupe(program.value.Field, &.{
        .{ .name = "schema", .value = .{ .uint32 = 1 } },
        .{ .name = "kind", .value = .{ .enumeration = kind } },
        .{ .name = "owner", .value = owner },
        .{ .name = "everyone", .value = everyone },
    }) };
}
