//! Run the documented sources through real authoring, assembly and native installation.
const std = @import("std");
const compiler = @import("compiler");
const program = @import("program");
const kernel = @import("kernel");
const image = @import("image");
const provenance = @import("suite_provenance");
const commands = @import("commands.zig");
const Dir = std.Io.Dir;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var run = try provenance.Run.startForSuite(
        init.arena.allocator(),
        init.io,
        args,
        "dsl-tutorial",
    );
    qualify(&run, args) catch |err| {
        try run.finish(@errorName(err));
        return err;
    };
    try run.finish(null);
    std.log.info("DSL tutorial PASS: {s}", .{run.evidence});
}

// The run step in build/tutorial.zig appends these paths in this order.
const Tools = struct {
    prepare: []const u8,
    compiler: []const u8,
    author: []const u8,
    sdk: []const u8,
    example: []const u8,
};

fn qualify(run: *provenance.Run, args: []const []const u8) !void {
    if (args.len != 6) return error.Usage;
    const tools: Tools = .{
        .prepare = args[1],
        .compiler = args[2],
        .author = args[3],
        .sdk = args[4],
        .example = args[5],
    };
    try run.capture();
    try recordCollision(run);
    const first = try run.arena.print("{s}/release-1", .{run.evidence});
    try prepare(run, tools, tools.example, first, "prepare-1");
    try duplicatePreparation(run, tools, first);
    const main_model = try author(run, tools.author, first, "product", "1");
    const modular = try author(run, tools.author, first, "product_modular", "1");
    try std.testing.expectEqualStrings(main_model, modular);
    const setup = try compile(run, tools.compiler, first, "product");
    const root = try run.arena.print("{s}/installed", .{run.evidence});
    const installed = try commands.action(run, setup, root, "install", &.{}, "install-1");
    try snapshot(run, installed, 1, true);
    const original = try read(run, try run.arena.print(
        "{s}/payload/README.txt",
        .{tools.example},
    ));
    try payload(run, root, "hello", original);
    const disabled = try commands.action(
        run,
        setup,
        root,
        "reconfigure",
        &.{ "--set", "enabled=false" },
        "disabled",
    );
    try snapshot(run, disabled, 1, false);
    try missing(run, try run.arena.print("{s}/current/hello/README.txt", .{root}));
    const enabled = try commands.action(
        run,
        setup,
        root,
        "reconfigure",
        &.{ "--set", "enabled=true" },
        "enabled",
    );
    try snapshot(run, enabled, 1, true);
    try payload(run, root, "hello", original);
    try invalidBoolean(run, tools, first);
    try failures(run, tools, first, setup, root);
    const second = try releaseTwo(run, tools);
    const upgraded = try commands.action(run, second, root, "update", &.{}, "update-2");
    try snapshot(run, upgraded, 2, true);
    try payload(run, root, "hello", release_two_payload);
    const removed = try commands.action(run, second, root, "uninstall", &.{}, "uninstall");
    const result = try std.json.parseFromSliceLeaky(kernel.Result, run.arena, removed, .{});
    try std.testing.expect(result.state == null);
    try missing(run, try run.arena.print("{s}/current", .{root}));
    try missing(run, try run.arena.print("{s}/.niobium-v2/installation.json", .{root}));
    try flow(run, tools, first);
    try summary(run, main_model);
}

fn recordCollision(run: *provenance.Run) !void {
    try commands.record(run, "collision-guard", .{ .marker = "original" });
    const path = try run.arena.print("{s}/collision-guard.json", .{run.evidence});
    const original = try read(run, path);
    try std.testing.expectError(
        error.PathAlreadyExists,
        commands.record(run, "collision-guard", .{ .marker = "replacement" }),
    );
    try std.testing.expectEqualStrings(original, try read(run, path));
}

fn summary(run: *provenance.Run, main_model: []const u8) !void {
    try commands.record(
        run,
        "summary",
        .{
            .suite = "dsl-tutorial",
            .status = "PASS",
            .normalized_model_sha256 = try program.digest(run.arena, main_model),
            .scenarios = &.{
                "install",
                "reconfigure",
                "update",
                "uninstall",
                "modular-parity",
                "observation-node-result",
                "diagnostics",
                "locked-input-refusal",
            },
        },
    );
}

fn prepare(
    run: *provenance.Run,
    tools: Tools,
    source: []const u8,
    out: []const u8,
    name: []const u8,
) !void {
    const stdout = try commands.success(
        run,
        name,
        &.{ tools.prepare, "--sdk", tools.sdk, "--source", source, "--out", out },
    );
    try std.testing.expectEqual(@as(usize, 0), stdout.len);
}

fn duplicatePreparation(run: *provenance.Run, tools: Tools, directory: []const u8) !void {
    const lock_path = try run.arena.print("{s}/inputs.lock.json", .{directory});
    const original = try read(run, lock_path);
    const refused = try commands.execute(run, "prepare-existing", &.{
        tools.prepare,
        "--sdk",
        tools.sdk,
        "--source",
        tools.example,
        "--out",
        directory,
    });
    try std.testing.expect(!refused.term.success());
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "PathAlreadyExists") != null);
    try std.testing.expectEqualStrings(original, try read(run, lock_path));
}

fn rewriteEnabled(
    run: *provenance.Run,
    directory: []const u8,
    name: []const u8,
    replacement: []const u8,
) !void {
    const source = try read(run, try run.arena.print("{s}/product.star", .{directory}));
    const rewritten = try std.mem.replaceOwned(
        u8,
        run.arena,
        source,
        "input(\"enabled\", value(\"bool\", True))",
        replacement,
    );
    try Dir.cwd().writeFile(run.io, .{
        .sub_path = try run.arena.print("{s}/{s}", .{ directory, name }),
        .data = rewritten,
    });
}

fn invalidBoolean(run: *provenance.Run, tools: Tools, directory: []const u8) !void {
    try rewriteEnabled(
        run,
        directory,
        "invalid_bool.star",
        "input(\"enabled\", value(\"bool\", \"yes\"))",
    );
    const path = try run.arena.print("{s}/invalid_bool.star", .{directory});
    const output = try run.arena.print("{s}/invalid_bool.program.json", .{directory});
    const rejected = try commands.execute(run, "invalid-boolean", &.{
        tools.author, "--source", path, "--out", output,
    });
    try std.testing.expect(!rejected.term.success());
    try std.testing.expect(std.mem.indexOf(u8, rejected.stderr, "invalid_bool.star:10:23") != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected.stderr, "bool required") != null);
    try missing(run, output);
}

fn author(
    run: *provenance.Run,
    executable: []const u8,
    directory: []const u8,
    name: []const u8,
    sequence: []const u8,
) ![]const u8 {
    const output = try run.arena.print("{s}/{s}.program.json", .{ directory, name });
    const stdout = try commands.success(
        run,
        try run.arena.print("author-{s}-{s}", .{
            std.fs.path.basename(directory), name,
        }),
        &.{
            executable,
            "--source",
            try run.arena.print("{s}/{s}.star", .{ directory, name }),
            "--out",
            output,
            "--source-map",
            try run.arena.print("{s}/{s}.sources.json", .{ directory, name }),
            "--arg",
            try run.arena.print("release_sequence={s}", .{sequence}),
        },
    );
    try std.testing.expectEqual(@as(usize, 0), stdout.len);
    return read(run, output);
}

fn compile(
    run: *provenance.Run,
    executable: []const u8,
    directory: []const u8,
    name: []const u8,
) ![]const u8 {
    const stdout = try commands.success(
        run,
        try run.arena.print("compile-{s}-{s}", .{
            std.fs.path.basename(directory), name,
        }),
        try commands.compileArgs(run, executable, directory, name),
    );
    try std.testing.expect(std.mem.indexOf(u8, stdout, "\"status\":\"ok\"") != null);
    const output = try run.arena.print("{s}/{s}.setup", .{ directory, name });
    const file = try Dir.cwd().openFile(run.io, output, .{});
    defer file.close(run.io);
    const source: image.Source = .{ .file = .{
        .handle = file,
        .length = (try file.stat(run.io)).size,
    } };
    const descriptor = try image.verify(run.arena, run.io, source, .{});
    if (@import("builtin").target.os.tag == .macos)
        try image.verifyAdhoc(run.arena, run.io, source, .{});
    try commands.record(run, try run.arena.print("image-{s}-{s}", .{
        std.fs.path.basename(directory), name,
    }), descriptor);
    return output;
}

const release_two_payload = "Hello from the Niobium DSL tutorial, release 2.\n";

fn releaseTwo(run: *provenance.Run, tools: Tools) ![]const u8 {
    const source = try run.arena.print("{s}/source-2", .{run.evidence});
    try Dir.cwd().createDirPath(run.io, try run.arena.print("{s}/payload", .{source}));
    try Dir.cwd().createDirPath(run.io, try run.arena.print("{s}/fallback", .{source}));
    const dir = try Dir.cwd().openDir(run.io, source, .{});
    defer dir.close(run.io);
    const sources = [_][]const u8{
        "product.star",        "product_modular.star", "model.star", "product_flow.star",
        "fallback/README.txt",
    };
    for (sources) |path| {
        try dir.writeFile(run.io, .{
            .sub_path = path,
            .data = try read(run, try run.arena.print("{s}/{s}", .{ tools.example, path })),
        });
    }
    try dir.writeFile(run.io, .{
        .sub_path = "payload/README.txt",
        .data = release_two_payload,
    });
    const second = try run.arena.print("{s}/release-2", .{run.evidence});
    try prepare(run, tools, source, second, "prepare-2");
    const model = try author(run, tools.author, second, "product", "2");
    const parsed = try program.model.decode(run.arena, model);
    try std.testing.expectEqual(@as(u32, 1), parsed.model_version);
    return compile(run, tools.compiler, second, "product");
}

fn failures(
    run: *provenance.Run,
    tools: Tools,
    directory: []const u8,
    setup: []const u8,
    root: []const u8,
) !void {
    const before = try commands.action(run, setup, root, "status", &.{}, "before-refusal");
    const existing = try read(run, setup);
    try rewriteEnabled(
        run,
        directory,
        "broken.star",
        "input(\"enabled\", value(\"string\", \"yes\"))",
    );
    const model = try author(run, tools.author, directory, "broken", "1");
    try std.testing.expect(model.len > 0);
    const rejected = try commands.execute(
        run,
        "invalid-type",
        try commands.compileArgs(run, tools.compiler, directory, "broken"),
    );
    try std.testing.expect(!rejected.term.success());
    const diagnostic = try std.json.parseFromSliceLeaky(struct {
        schema: u32,
        status: []const u8,
        diagnostic: ?compiler.pipeline.Diagnostic,
    }, run.arena, rejected.stderr[0..(std.mem.indexOf(u8, rejected.stderr, "\n") orelse
        return error.MissingDiagnostic)], .{});
    const found = diagnostic.diagnostic orelse return error.MissingDiagnostic;
    try std.testing.expectEqual(.type_mismatch, found.code);
    try std.testing.expectEqualStrings("deploy", found.object);
    const location = found.source orelse return error.MissingLocation;
    try std.testing.expect(std.mem.endsWith(u8, location.file, "broken.star"));
    try std.testing.expectEqual(@as(u32, 37), location.line);
    try std.testing.expectEqual(@as(u32, 5), location.column);
    const content_path = try run.arena.print("{s}/content", .{directory});
    const old_content = try read(run, content_path);
    try Dir.cwd().writeFile(run.io, .{ .sub_path = content_path, .data = "corrupt" });
    const mismatch = try commands.execute(
        run,
        "locked-input-refusal",
        try commands.compileArgs(run, tools.compiler, directory, "product"),
    );
    try std.testing.expect(!mismatch.term.success());
    try std.testing.expect(std.mem.indexOf(u8, mismatch.stderr, "LockMismatch") != null);
    try Dir.cwd().writeFile(run.io, .{ .sub_path = content_path, .data = old_content });
    try std.testing.expectEqualStrings(existing, try read(run, setup));
    const after = try commands.action(run, setup, root, "status", &.{}, "after-refusal");
    try std.testing.expectEqualStrings(before, after);
}

fn flow(run: *provenance.Run, tools: Tools, directory: []const u8) !void {
    const model = try author(run, tools.author, directory, "product_flow", "1");
    try std.testing.expect(model.len > 0);
    const setup = try compile(run, tools.compiler, directory, "product_flow");
    const root = try run.arena.print("{s}/flow-installed", .{run.evidence});
    const installed = try commands.action(run, setup, root, "install", &.{}, "flow-install");
    try snapshot(run, installed, 1, true);
    const prefix = @tagName(@import("builtin").target.os.tag);
    try payload(
        run,
        root,
        prefix,
        try read(run, try run.arena.print("{s}/payload/README.txt", .{tools.example})),
    );
    const changed = try commands.action(
        run,
        setup,
        root,
        "reconfigure",
        &.{ "--set", "primary=false" },
        "flow-fallback",
    );
    try snapshot(run, changed, 1, true);
    try payload(
        run,
        root,
        prefix,
        try read(run, try run.arena.print("{s}/fallback/README.txt", .{tools.example})),
    );
    const removed = try commands.action(run, setup, root, "uninstall", &.{}, "flow-uninstall");
    const result = try std.json.parseFromSliceLeaky(kernel.Result, run.arena, removed, .{});
    try std.testing.expect(result.state == null);
}

fn read(run: *provenance.Run, path: []const u8) ![]const u8 {
    return Dir.cwd().readFileAlloc(
        run.io,
        path,
        run.arena,
        .limited((@import("contracts").Limits{}).test_attachment_bytes),
    );
}

fn snapshot(run: *provenance.Run, bytes: []const u8, sequence: u32, present: bool) !void {
    const result = try std.json.parseFromSliceLeaky(kernel.Result, run.arena, bytes, .{});
    const state = result.state orelse return error.MissingState;
    try std.testing.expectEqual(sequence, state.release_sequence);
    try std.testing.expectEqual(present, state.roots[0].resources.len > 0);
}

fn payload(
    run: *provenance.Run,
    root: []const u8,
    prefix: []const u8,
    expected: []const u8,
) !void {
    const path = try run.arena.print("{s}/current/{s}/README.txt", .{ root, prefix });
    try std.testing.expectEqualStrings(expected, try read(run, path));
}

fn missing(run: *provenance.Run, path: []const u8) !void {
    try std.testing.expectError(error.FileNotFound, Dir.cwd().access(run.io, path, .{}));
}
