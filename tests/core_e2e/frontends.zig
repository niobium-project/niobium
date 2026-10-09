//! Equivalent public author programs are compiled and executed as real installers.
const std = @import("std");
const compiler = @import("compiler");
const program = @import("program");
const primitives = @import("host_primitives");
const provenance = @import("suite_provenance");
const prepare = @import("prepare.zig");
const commands = @import("commands.zig");
const Dir = std.Io.Dir;

pub fn qualify(run: *provenance.Run, args: []const []const u8, inputs: prepare.Prepared) !void {
    const prepared = try alias(run, inputs);
    const hash = prepared.assets.consumer.sha256;
    const length = try run.arena.print("{d}", .{prepared.assets.consumer.bytes});
    const target = @tagName(try primitives.currentTarget());
    var first: ?[]const u8 = null;
    for ([_][]const u8{ "native", "c", "starlark" }, 0..) |language, index| {
        const name = try run.arena.print("frontend-{s}", .{language});
        const path = try run.arena.print("{s}/{s}.program.json", .{ prepared.directory, name });
        const command: []const []const u8 = if (index < 2)
            &.{ args[index + 7], path, hash, length, target }
        else
            &.{
                args[9],
                "--source",
                args[10],
                "--out",
                path,
                "--arg",
                try run.arena.print("library_sha256={s}", .{hash}),
                "--arg",
                try run.arena.print("library_bytes={s}", .{length}),
                "--arg",
                try run.arena.print("target={s}", .{target}),
            };
        const stdout = try commands.success(run, name, command);
        try std.testing.expectEqual(@as(usize, 0), stdout.len);
        const model = try Dir.cwd().readFileAlloc(run.io, path, run.arena, .limited(1 << 20));
        if (first) |bytes| try std.testing.expectEqualStrings(bytes, model) else first = model;
        const setup = try commands.compile(run, args[5], prepared, name);
        const root = try run.arena.print("{s}/install-{s}", .{ run.evidence, name });
        const installed = try commands.action(
            run,
            setup,
            root,
            "install",
            &.{},
            try run.arena.print("{s}-install", .{name}),
        );
        try std.testing.expect(installed.len > 0);
        const description = try Dir.cwd().readFileAlloc(
            run.io,
            try run.arena.print("{s}/current/toolchain/environment.txt", .{root}),
            run.arena,
            .limited(4096),
        );
        try std.testing.expect(std.mem.indexOf(u8, description, "label=Toolchain\n") != null);
        const removed = try commands.action(
            run,
            setup,
            root,
            "uninstall",
            &.{},
            try run.arena.print("{s}-uninstall", .{name}),
        );
        try std.testing.expect(std.mem.indexOf(u8, removed, "\"state\":null") != null);
    }
    try commands.record(run, "frontends", .{
        .id = "N2-AUTH-03",
        .status = "PASS",
        .target = target,
        .model_sha256 = try program.digest(run.arena, first orelse return error.MissingModel),
        .executed = &.{ "native", "c", "starlark" },
    });
}

fn alias(run: *provenance.Run, source: prepare.Prepared) !prepare.Prepared {
    var result = source;
    const inputs = try run.arena.dupe(prepare.Input, source.inputs);
    const locked = try run.arena.alloc(compiler.lock.Input, inputs.len);
    for (inputs, locked) |*input, *entry| {
        if (std.mem.eql(u8, input.entry.id, "consumer")) input.entry.id = "tools";
        entry.* = input.entry;
    }
    result.inputs = inputs;
    result.lock_path = try run.arena.print("{s}/frontends.lock.json", .{source.directory});
    try Dir.cwd().writeFile(
        run.io,
        .{
            .sub_path = result.lock_path,
            .data = try compiler.lock.encode(run.arena, .{ .inputs = locked }),
        },
    );
    return result;
}
