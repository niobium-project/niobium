//! Native reference author uses the same public Builder as hosted frontends.
const std = @import("std");
const compiler = @import("compiler");
const program = compiler.program;
const model = program.model;
fn text(value: []const u8) model.Binding {
    return .{ .literal = .{ .text = value } };
}
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 4 and args.len != 5) return error.Usage;
    const target = if (args.len == 5)
        std.meta.stringToEnum(program.profile.Target, args[4]) orelse return error.InvalidTarget
    else
        program.profile.Target.@"aarch64-macos";
    var builder = try compiler.author.Builder.init(arena, "reference", 1, 1, .{
        .id = "niobium.user.component",
        .target = target,
        .primitives = &.{
            .{ .id = "content.tree", .version = 1 },
            .{ .id = "machine.facts", .version = 1 },
        },
    });
    try builder.root(.{ .id = "application" });
    try builder.stateRoot("application");
    const hash = args[2];
    const library_bytes = try std.fmt.parseInt(u64, args[3], 10);
    try builder.library(
        .{ .id = "tools", .member = "libs/tools.wasm", .sha256 = hash, .bytes = library_bytes },
    );
    try builder.input(.{ .id = "enabled", .default = .{ .boolean = true } });
    try builder.input(.{ .id = "label", .default = .{ .text = "Toolchain" } });
    try addGrant(&builder);
    const zeros: [32]u8 = @splat(0);
    const reference: program.value.Value = .{ .record = &.{
        .{ .name = "format", .value = .{ .enumeration = "posix-pax-v1" } },
        .{ .name = "sha256", .value = .{ .bytes = &zeros } },
        .{ .name = "bytes", .value = .{ .uint64 = 10240 } },
    } };
    const request: model.Binding = .{ .record = &.{
        .{ .name = "root", .binding = text("application") },
        .{ .name = "grant", .binding = text("owned") },
        .{ .name = "prefix", .binding = text("toolchain") },
        .{ .name = "content", .binding = .{ .literal = reference } },
        .{ .name = "label", .binding = .{ .input = "label" } },
        .{ .name = "platform", .binding = .{ .observation = .{
            .id = "machine",
            .fields = &.{"os"},
        } } },
        .{ .name = "enabled", .binding = .{ .input = "enabled" } },
        .{ .name = "previous", .binding = .previous_state },
    } };
    try builder.observe(
        .{
            .id = "machine",
            .primitive = .{ .id = "machine.facts", .version = 1 },
            .function = "facts",
        },
    );
    try builder.call(.{
        .id = "configure",
        .library = "tools",
        .interface = "niobium:reference/installer@1.0.0",
        .function = "build",
        .arguments = &.{request},
        .grants = &.{"owned"},
        .result_role = .plan,
    });
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = args[1],
        .data = try builder.emit(),
        .flags = .{ .exclusive = true },
    });
}

fn addGrant(builder: *compiler.author.Builder) compiler.author.Error!void {
    try builder.grant(.{
        .id = "owned",
        .root = "application",
        .primitive = .{ .id = "content.tree", .version = 1 },
        .max_entries = 64,
        .max_bytes = 1 << 20,
        .file_access = .{
            .kind = .file,
            .owner = .fromBits(3),
            .everyone = .fromBits(1),
        },
        .directory_access = .{
            .kind = .directory,
            .owner = .fromBits(3),
            .everyone = .fromBits(1),
        },
    });
}
