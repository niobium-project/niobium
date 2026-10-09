//! Prepare exact tutorial inputs; authoring and installer compilation remain separate commands.
const std = @import("std");
const compiler = @import("compiler");
const content = @import("content");
const contracts = @import("contracts");
const Dir = std.Io.Dir;
const limits: contracts.Limits = .{};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const options = try parse(args);
    try prepare(arena, init.io, options);
}

const Options = struct { sdk: []const u8, source: []const u8, out: []const u8 };

fn parse(args: []const []const u8) error{Usage}!Options {
    if (args.len != 7) return error.Usage;
    var sdk: ?[]const u8 = null;
    var source: ?[]const u8 = null;
    var out: ?[]const u8 = null;
    for (0..3) |index| {
        const flag = args[index * 2 + 1];
        const value = args[index * 2 + 2];
        if (value.len == 0 or value.len > limits.path_bytes) return error.Usage;
        const destination = if (std.mem.eql(u8, flag, "--sdk"))
            &sdk
        else if (std.mem.eql(u8, flag, "--source"))
            &source
        else if (std.mem.eql(u8, flag, "--out"))
            &out
        else
            return error.Usage;
        if (destination.* != null) return error.Usage;
        destination.* = value;
    }
    return .{
        .sdk = sdk orelse return error.Usage,
        .source = source orelse return error.Usage,
        .out = out orelse return error.Usage,
    };
}

fn prepare(arena: std.mem.Allocator, io: std.Io, options: Options) !void {
    try Dir.cwd().createDir(io, options.out, .default_dir);
    const out = try Dir.cwd().openDir(io, options.out, .{});
    defer out.close(io);
    const source = try Dir.cwd().openDir(io, options.source, .{});
    defer source.close(io);
    const sdk = try Dir.cwd().openDir(io, options.sdk, .{});
    defer sdk.close(io);
    const sdk_inputs = try sdkInputs(arena, io, sdk, out);
    const package = sdk_inputs.package;
    const files = sdk_inputs.files;
    var entries = sdk_inputs.entries;
    const primary = try payload(arena, io, source, out, "payload/README.txt", "content");
    const fallback = try payload(arena, io, source, out, "fallback/README.txt", "fallback");
    try entries.appendSlice(arena, &.{ primary, fallback });
    try out.writeFile(
        io,
        .{
            .sub_path = "inputs.lock.json",
            .data = try compiler.lock.encode(arena, .{ .inputs = entries.items }),
        },
    );
    try constants(arena, io, out, package, files, primary, fallback);
    const sources = [_][]const u8{
        "product.star", "model.star", "product_modular.star", "product_flow.star",
    };
    for (sources) |name| {
        const text = try source.readFileAlloc(io, name, arena, .limited(limits.program_bytes));
        try out.writeFile(io, .{ .sub_path = name, .data = text });
    }
}

const SDKInputs = struct {
    entries: std.ArrayList(compiler.lock.Input),
    package: compiler.runtime_package.Package,
    files: compiler.lock.Input,
};

fn sdkInputs(arena: std.mem.Allocator, io: std.Io, sdk: Dir, out: Dir) !SDKInputs {
    var entries: std.ArrayList(compiler.lock.Input) = .empty;
    const suffix = if (@import("builtin").target.os.tag == .windows) ".exe" else "";
    const maximum = limits.native_image_bytes;
    const runtime_path = "bin/niobium-runtime-v2" ++ suffix;
    const metadata_path = "share/niobium/runtime-package.json";
    const metadata_maximum = limits.manifest_bytes;
    var runtime = try copy(arena, io, sdk, out, runtime_path, "runtime", .runtime, maximum);
    var metadata = try copy(
        arena,
        io,
        sdk,
        out,
        metadata_path,
        "runtime-metadata",
        .runtime_metadata,
        metadata_maximum,
    );
    const bytes = try out.readFileAlloc(
        io,
        "runtime-metadata",
        arena,
        .limited(limits.manifest_bytes),
    );
    const package = try compiler.runtime_package.decode(arena, bytes);
    if (!std.mem.eql(u8, package.template_sha256, runtime.sha256) or
        package.template_bytes != runtime.bytes) return error.RuntimeMismatch;
    runtime.target = package.profile.target;
    runtime.version = package.version;
    runtime.dependencies = &.{"runtime-metadata"};
    metadata.version = package.version;
    try entries.appendSlice(arena, &.{ runtime, metadata });
    const worker_path = "bin/niobium-component-worker" ++ suffix;
    const worker = try copy(arena, io, sdk, out, worker_path, "worker", .tool, maximum);
    try entries.append(arena, worker);
    const files_path = "lib/niobium/stdlib/files.wasm";
    const files_maximum = limits.component_bytes;
    const files = try copy(arena, io, sdk, out, files_path, "files", .library, files_maximum);
    try entries.append(arena, files);
    if (package.profile.target == .@"aarch64-macos") {
        const signer_path = "bin/rcodesign" ++ suffix;
        const signer = try copy(arena, io, sdk, out, signer_path, "signer", .tool, maximum);
        try entries.append(arena, signer);
    }
    return .{ .entries = entries, .package = package, .files = files };
}

fn copy(
    arena: std.mem.Allocator,
    io: std.Io,
    source: Dir,
    out: Dir,
    path: []const u8,
    id: []const u8,
    kind: compiler.lock.Kind,
    maximum: u64,
) !compiler.lock.Input {
    const file = try source.openFile(io, path, .{ .follow_symlinks = false });
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.kind != .file or stat.size > maximum) return error.InputLimit;
    const output = try out.createFile(io, id, .{
        .exclusive = true,
        .permissions = if (kind == .runtime or kind == .tool)
            .executable_file
        else
            .default_file,
    });
    defer output.close(io);
    var buffer: [64 << 10]u8 = undefined; // SAFETY: positional reads fill every copied slice.
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var offset: u64 = 0;
    while (offset < stat.size) {
        const count = std.math.cast(usize, @min(stat.size - offset, buffer.len)) orelse
            return error.InputLimit;
        if (try file.readPositionalAll(io, buffer[0..count], offset) != count)
            return error.InputChanged;
        try output.writeStreamingAll(io, buffer[0..count]);
        hash.update(buffer[0..count]);
        offset += count;
    }
    try output.sync(io);
    return .{
        .id = id,
        .kind = kind,
        .version = "1",
        .origin = id,
        .sha256 = try arena.dupe(u8, &std.fmt.bytesToHex(hash.finalResult(), .lower)),
        .bytes = stat.size,
    };
}

fn payload(
    arena: std.mem.Allocator,
    io: std.Io,
    source: Dir,
    out: Dir,
    path: []const u8,
    id: []const u8,
) !compiler.lock.Input {
    const bytes = try source.readFileAlloc(io, path, arena, .limited(limits.program_bytes));
    const tree = try content.fromEntries(arena, &.{.{
        .path = "README.txt",
        .mode = 0o644,
        .body = content.Body.bytes(bytes),
    }}, limits);
    const file = try out.createFile(io, id, .{ .exclusive = true });
    defer file.close(io);
    var buffer: [64 << 10]u8 = undefined; // SAFETY: the writer owns the scratch buffer.
    var writer = file.writer(io, &buffer);
    const reference = try content.writeTar(arena, io, tree, &writer.interface, limits);
    try writer.interface.flush();
    try file.sync(io);
    return .{
        .id = id,
        .kind = .content,
        .version = "1",
        .origin = id,
        .sha256 = try arena.dupe(u8, &std.fmt.bytesToHex(reference.sha256, .lower)),
        .bytes = reference.bytes,
    };
}

fn constants(
    arena: std.mem.Allocator,
    io: std.Io,
    out: Dir,
    package: compiler.runtime_package.Package,
    files: compiler.lock.Input,
    primary: compiler.lock.Input,
    fallback: compiler.lock.Input,
) !void {
    var text: std.Io.Writer.Allocating = .init(arena);
    try text.writer.print(
        "TARGET = \"{s}\"\nPROFILE = \"{s}\"\nPRIMITIVES = {{",
        .{ @tagName(package.profile.target), package.profile.id },
    );
    for (package.profile.primitives, 0..) |item, index| {
        if (index != 0) try text.writer.writeAll(", ");
        try text.writer.print("\"{s}\": {d}", .{ item.id, item.version });
    }
    try text.writer.print(
        "}}\nFILES_SHA256 = \"{s}\"\nFILES_BYTES = {d}\n",
        .{ files.sha256, files.bytes },
    );
    const inputs = [_]compiler.lock.Input{ primary, fallback };
    const names = [_][]const u8{ "CONTENT", "FALLBACK" };
    for (inputs, names) |input, name| {
        try text.writer.print(
            "{s}_SHA256 = \"{s}\"\n{s}_BYTES = {d}\n{s}_DIGEST = b\"",
            .{ name, input.sha256, name, input.bytes, name },
        );
        const digest = contracts.ids.parseHex32(input.sha256) orelse return error.InvalidDigest;
        for (digest) |byte| try text.writer.print("\\x{x:0>2}", .{byte});
        try text.writer.writeAll("\"\n");
    }
    try out.writeFile(io, .{ .sub_path = "inputs.star", .data = text.written() });
}

test "tutorial preparation requires one occurrence of every named directory" {
    try std.testing.expectError(error.Usage, parse(&.{ "prepare", "--sdk", "a" }));
    try std.testing.expectError(error.Usage, parse(&.{
        "prepare", "--sdk", "a", "--sdk", "b", "--out", "c",
    }));
    const options = try parse(&.{
        "prepare", "--out", "result", "--source", "source", "--sdk", "sdk",
    });
    try std.testing.expectEqualStrings("sdk", options.sdk);
}
