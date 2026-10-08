//! Publish a runtime/profile identity record without running the target executable.

const std = @import("std");
const compiler = @import("compiler");
const program = @import("program");
const image = @import("image");
const contracts = @import("contracts");
const primitives = @import("host_primitives");
const options = @import("options.zig");
const storage = @import("workspace.zig");

pub fn run(init: std.process.Init, args: options.Options) !void {
    const arena = init.arena.allocator();
    const target = std.meta.stringToEnum(program.profile.Target, args.target.?) orelse
        return error.Usage;
    const work = try storage.Workspace.init(arena, init.io, args.output);
    defer work.deinit();
    const input = try std.Io.Dir.cwd().openFile(init.io, args.template.?, .{});
    defer input.close(init.io);
    const snapshot = try work.dir.createFile(
        init.io,
        "template",
        .{ .exclusive = true, .read = true },
    );
    defer snapshot.close(init.io);
    const original = try storage.source(init.io, input);
    const digest = try storage.digest(init.io, original, snapshot);
    const source = try storage.source(init.io, snapshot);
    const layout = try image.native.inspect(arena, init.io, source, .{});
    const actual: program.profile.Target = switch (layout.format) {
        .macho => if (layout.cpu == .aarch64) .@"aarch64-macos" else return error.TargetMismatch,
        .elf => if (layout.cpu == .x86_64) .@"x86_64-linux" else return error.TargetMismatch,
        .pe => if (layout.cpu == .x86_64) .@"x86_64-windows" else return error.TargetMismatch,
    };
    if (actual != target) return error.TargetMismatch;
    var slot: [image.descriptor.size]u8 = undefined; // SAFETY: read fills the complete slot.
    try source.read(init.io, layout.slot.offset, &slot);
    try image.descriptor.checkTemplate(&slot);
    const package: compiler.runtime_package.Package = .{
        .version = args.version.?,
        .template_sha256 = &contracts.ids.hexDigest(digest),
        .template_bytes = source.size(),
        .profile = primitives.runtimeProfile(target),
    };
    const bytes = try std.json.Stringify.valueAlloc(arena, package, .{ .whitespace = .indent_2 });
    const validated = try compiler.runtime_package.decode(arena, bytes);
    std.debug.assert(validated.template_bytes == source.size());
    const output = try work.dir.createFile(init.io, "package.json", .{ .exclusive = true });
    {
        defer output.close(init.io);
        try output.writeStreamingAll(init.io, bytes);
        try output.sync(init.io);
    }
    try work.publish("package.json");
}
