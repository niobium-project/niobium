//! Native templates, large payloads, tampering and retained executable code evidence.

const std = @import("std");
const builtin = @import("builtin");
const core = @import("core");
const image = @import("image");
const Dir = std.Io.Dir;

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 4) return error.Usage;
    const evidence = try directory(a, init.io);
    const dir = try Dir.cwd().openDir(init.io, evidence, .{});
    defer dir.close(init.io);
    const payload = try dir.createFile(init.io, "payload", .{ .read = true });
    defer payload.close(init.io);
    const block: [64 << 10]u8 = @splat(0x61);
    for (0..32) |_| try payload.writeStreamingAll(init.io, &block);
    var results: std.ArrayList(Result) = .empty;
    for (args[1..], 0..) |path, index| {
        const result = try check(a, init.io, path, payload, dir, evidence, index);
        try results.append(a, result);
    }
    const bytes = try std.json.Stringify.valueAlloc(a, .{
        .suite = "image",
        .status = "PASS",
        .argv = args,
        .results = results.items,
    }, .{ .whitespace = .indent_2 });
    try dir.writeFile(init.io, .{ .sub_path = "report.json", .data = bytes });
    std.log.info("N2-IMAGE-02 PASS: {s}", .{evidence});
}

const Result = struct {
    format: image.Format,
    cpu: image.Cpu,
    code_preserved: bool,
    native_prefix_preserved: bool,
    native_prefix_sha256: [32]u8,
    native_execution: bool,
    payload_bytes: u64,
    artifact_sha256: [32]u8,
};

fn check(
    a: std.mem.Allocator,
    io: std.Io,
    template_path: []const u8,
    payload: std.Io.File,
    dir: Dir,
    evidence: []const u8,
    index: usize,
) !Result {
    const template = try Dir.cwd().openFile(io, template_path, .{});
    defer template.close(io);
    const original = try source(io, template);
    const layout = try image.native.inspect(a, io, original, .{});
    const name = try a.print("setup-{d}{s}", .{ index, if (layout.format == .pe) ".exe" else "" });
    const output = try dir.createFile(io, name, .{ .exclusive = true, .read = true });
    defer output.close(io);
    const payload_source = try source(io, payload);
    const assembled = try image.assemble(a, io, original, .bytes("NIOBIUM_IMAGE_V2_OK"), .{
        .source = payload_source,
        .length = payload_source.size(),
    }, output, .{});
    if (std.Io.File.Permissions.has_executable_bit) {
        try output.setPermissions(io, .fromMode(0o755));
    }
    try output.sync(io);
    const product = try source(io, output);
    const verified = try image.verify(a, io, product, .{});
    try std.testing.expectEqualDeep(assembled.descriptor, verified);
    try sameCode(io, original, product, layout.code);
    try tamper(a, io, output, verified.payload.offset);
    try tamper(a, io, output, layout.code[0].offset);
    if (try layout.slot.end() < verified.prefix_bytes) {
        try tamper(a, io, output, try layout.slot.end());
    }
    const header_byte: u64 = if (layout.format == .pe) layout.pe_checksum - 80 else 24;
    try tamper(a, io, output, header_byte);
    if (layout.format == .macho) try maskedVmSize(a, io, output, layout);
    const path = try a.print("{s}/{s}", .{ evidence, name });
    const native_run = try execute(a, io, path, layout);
    const final = try Dir.cwd().openFile(io, path, .{});
    defer final.close(io);
    const final_source = try source(io, final);
    const final_value = try image.verify(a, io, final_source, .{});
    try std.testing.expectEqualDeep(verified, final_value);
    try sameCode(io, original, final_source, layout.code);
    const digest = try hash(io, final_source, .{ .offset = 0, .length = final_source.size() });
    return .{
        .format = layout.format,
        .cpu = layout.cpu,
        .code_preserved = true,
        .native_prefix_preserved = true,
        .native_prefix_sha256 = verified.native_prefix_sha256,
        .native_execution = native_run,
        .payload_bytes = verified.payload.length,
        .artifact_sha256 = digest,
    };
}

fn source(io: std.Io, file: std.Io.File) !image.Source {
    return .{ .file = .{ .handle = file, .length = (try file.stat(io)).size } };
}

fn hash(io: std.Io, input: image.Source, range: image.Range) ![32]u8 {
    var state: std.crypto.hash.sha2.Sha256 = .init(.{});
    var buffer: [64 << 10]u8 = undefined; // SAFETY: source.read fills each hashed slice.
    var offset: u64 = 0;
    while (offset < range.length) {
        const length = std.math.cast(usize, @min(buffer.len, range.length - offset)) orelse
            return error.ImageLimit;
        try input.read(io, range.offset + offset, buffer[0..length]);
        state.update(buffer[0..length]);
        offset += length;
    }
    return state.finalResult();
}

fn sameCode(
    io: std.Io,
    old: image.Source,
    new: image.Source,
    ranges: []const image.Range,
) !void {
    for (ranges) |range| {
        const before = try hash(io, old, range);
        const after = try hash(io, new, range);
        try std.testing.expectEqualSlices(u8, &before, &after);
    }
}

fn tamper(a: std.mem.Allocator, io: std.Io, file: std.Io.File, offset: u64) !void {
    const input = try source(io, file);
    var byte: [1]u8 = undefined; // SAFETY: read fills the byte before mutation.
    try input.read(io, offset, &byte);
    byte[0] ^= 1;
    try file.writePositionalAll(io, &byte, offset);
    try std.testing.expectError(error.ImageDigest, image.verify(a, io, input, .{}));
    byte[0] ^= 1;
    try file.writePositionalAll(io, &byte, offset);
}

fn maskedVmSize(
    arena: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    layout: image.native.Layout,
) !void {
    const input = try source(io, file);
    const offset = layout.linkedit_command + 32;
    var original: [8]u8 = undefined; // SAFETY: source fills the complete native field.
    try input.read(io, offset, &original);
    const extent = input.size() - layout.linkedit_offset;
    std.debug.assert(extent > 0);
    for ([_]u64{ 0, extent - 1, 1 << 40 }) |invalid| {
        var bytes: [8]u8 = undefined; // SAFETY: writeInt initializes the mutated field.
        std.mem.writeInt(u64, &bytes, invalid, .little);
        try file.writePositionalAll(io, &bytes, offset);
        const result = image.verify(arena, io, input, .{});
        try file.writePositionalAll(io, &original, offset);
        try std.testing.expectError(error.ImageInvalid, result);
    }
    try input.read(io, layout.linkedit_command + 24, &original);
    var overlap: [8]u8 = undefined; // SAFETY: writeInt initializes the replacement address.
    std.mem.writeInt(u64, &overlap, layout.other_vm_end - 1, .little);
    try file.writePositionalAll(io, &overlap, layout.linkedit_command + 24);
    const result = image.verify(arena, io, input, .{});
    try file.writePositionalAll(io, &original, layout.linkedit_command + 24);
    try std.testing.expectError(error.ImageInvalid, result);
}

fn execute(a: std.mem.Allocator, io: std.Io, path: []const u8, layout: image.native.Layout) !bool {
    const format: image.Format = switch (builtin.target.os.tag) {
        .macos => .macho,
        .windows => .pe,
        .linux => .elf,
        else => return false,
    };
    const cpu: image.Cpu = switch (builtin.target.cpu.arch) {
        .aarch64 => .aarch64,
        .x86_64 => .x86_64,
        else => return false,
    };
    if (layout.format != format or layout.cpu != cpu) return false;
    if (format == .macho) {
        const signed = try run(a, io, &.{ "/usr/bin/codesign", "--force", "--sign", "-", path });
        try std.testing.expect(signed.term.success());
        const checked = try run(a, io, &.{ "/usr/bin/codesign", "--verify", "--strict", path });
        try std.testing.expect(checked.term.success());
    }
    const result = try run(a, io, &.{path});
    try std.testing.expect(result.term.success());
    try std.testing.expectEqualStrings("NIOBIUM_IMAGE_V2_OK\n", result.stdout);
    return true;
}

fn run(a: std.mem.Allocator, io: std.Io, argv: []const []const u8) !std.process.RunResult {
    return std.process.run(a, io, .{
        .argv = argv,
        .stdout_limit = .limited(64 << 10),
        .stderr_limit = .limited(64 << 10),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } },
    });
}

fn directory(a: std.mem.Allocator, io: std.Io) ![]const u8 {
    var stamp: std.Io.Writer.Allocating = .init(a);
    const now = std.Io.Clock.real.now(io).toMilliseconds();
    try core.crash.writeUtc(&stamp.writer, @divTrunc(now, 1000));
    var random: [8]u8 = undefined; // SAFETY: random fills the unique suffix.
    io.random(&random);
    const path = try a.print(".evidence/image/{s}-{s}", .{
        stamp.written(), std.fmt.bytesToHex(random, .lower),
    });
    try Dir.cwd().createDirPath(io, path);
    return Dir.cwd().realPathFileAlloc(io, path, a);
}
