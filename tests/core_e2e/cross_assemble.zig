//! This published Linux tool needs only its input directory and system libraries, not a checkout.
const std = @import("std");
const compiler = @import("compiler");
const program = @import("program");
const image = @import("image");
const Dir = std.Io.Dir;
const build_host = @tagName(@import("builtin").cpu.arch) ++ "-" ++
    @tagName(@import("builtin").os.tag);

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 3) return error.Usage;
    const inputs = try Dir.cwd().realPathFileAlloc(init.io, args[1], a);
    const output = try Dir.cwd().realPathFileAlloc(init.io, args[2], a);
    for ([_]program.profile.Target{
        .@"aarch64-macos", .@"x86_64-windows", .@"x86_64-linux",
    }) |target| {
        const source = try std.fs.path.join(a, &.{ inputs, @tagName(target) });
        const destination = try std.fs.path.join(a, &.{ output, @tagName(target) });
        try Dir.cwd().createDir(init.io, destination, .default_dir);
        for ([_][]const u8{ "files", "tools-v1", "tools-v2", "tools-invalid" }) |name| {
            const publication = if (std.mem.eql(u8, name, "tools-v2") or
                std.mem.eql(u8, name, "tools-invalid"))
                try std.fs.path.join(a, &.{ source, "upgrade" })
            else
                source;
            try assemble(a, init.io, inputs, publication, destination, target, name);
        }
    }
}

fn assemble(
    a: std.mem.Allocator,
    io: std.Io,
    inputs: []const u8,
    source: []const u8,
    destination: []const u8,
    target: program.profile.Target,
    name: []const u8,
) !void {
    const lock_path = try std.fs.path.join(a, &.{ source, "inputs.lock.json" });
    const locked = try compiler.lock.decode(
        a,
        try Dir.cwd().readFileAlloc(io, lock_path, a, .limited(1 << 20)),
    );
    const setup = try a.print("{s}/{s}.setup", .{ destination, name });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(
        a,
        &.{
            try std.fs.path.join(a, &.{ inputs, "compiler" }),
            "compile",
            "--program",
            try a.print("{s}/{s}.program.json", .{ source, name }),
            "--lock",
            lock_path,
            "--runtime",
            "runtime",
            "--runtime-metadata",
            "runtime-metadata",
            "--worker",
            "worker",
            "--output",
            setup,
        },
    );
    if (target == .@"aarch64-macos") try argv.appendSlice(a, &.{ "--signer", "signer" });
    for (locked.inputs) |entry| {
        try argv.appendSlice(
            a,
            &.{ "--input", try a.print("{s}={s}/{s}", .{ entry.id, source, entry.id }) },
        );
    }
    const result = try std.process.run(a, io, .{
        .argv = argv.items,
        .stdout_limit = .limited(1 << 20),
        .stderr_limit = .limited(1 << 20),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(60), .clock = .awake } },
    });
    try Dir.cwd().writeFile(io, .{
        .sub_path = try a.print("{s}/{s}.build.json", .{ destination, name }),
        .data = try std.json.Stringify.valueAlloc(a, .{
            .host = build_host,
            .target = target,
            .argv = argv.items,
            .term = result.term,
            .stdout = result.stdout,
            .stderr = result.stderr,
        }, .{}),
    });
    if (!result.term.success()) {
        std.log.err("{s}/{s}: {s}", .{ @tagName(target), name, result.stderr });
        return error.AssemblyFailed;
    }
    const file = try Dir.cwd().openFile(io, setup, .{});
    defer file.close(io);
    const view: image.Source = .{ .file = .{ .handle = file, .length = (try file.stat(io)).size } };
    const descriptor = try image.verify(a, io, view, .{});
    if (target == .@"aarch64-macos") try image.verifyAdhoc(a, io, view, .{});
    const expected = program.find(compiler.lock.Input, locked.inputs, "runtime") orelse
        return error.RuntimeMissing;
    try std.testing.expectEqualStrings(
        expected.sha256,
        &std.fmt.bytesToHex(descriptor.template_sha256, .lower),
    );
}
