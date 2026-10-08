//! Product assembly must work with copied release tools and denied repository/toolchain access.

const std = @import("std");
const compiler = @import("compiler");
const program = @import("program");
const world = @import("world.zig");
const World = world.World;
const Programs = @import("authoring.zig").Programs;
const expect = world.expect;

pub const Setups = struct {
    files: []const u8,
    v1: []const u8,
    v2: []const u8,
    missing: []const u8,
    missing_library: []const u8,
    changed_release: []const u8,
};

pub fn build(w: *World, programs: Programs) !Setups {
    try w.copy(w.tools.compiler, try w.temporary("compiler"));
    try w.copy(w.tools.runtime, try w.temporary("runtime"));
    try sandbox(w);
    try isolationControls(w, programs.v1);
    const files = try fileProgram(w);
    var missing = try program.decode(w.arena, try w.read(programs.v2));
    missing.upgrades = &.{};
    const missing_path = try w.path("missing-migration.program");
    try w.write(missing_path, try program.encode(w.arena, missing));
    var no_library_rule = try program.decode(w.arena, try w.read(programs.v2));
    const instances = try w.arena.dupe(program.Instance, no_library_rule.instances);
    instances[0].migrations = &.{};
    no_library_rule.instances = instances;
    const no_library_path = try w.path("missing-library-migration.program");
    try w.write(no_library_path, try program.encode(w.arena, no_library_rule));
    var changed_release = try program.decode(w.arena, try w.read(programs.v1));
    const inputs = try w.arena.dupe(program.Input, changed_release.inputs);
    inputs[0].default = "changed-without-new-release";
    changed_release.inputs = inputs;
    const changed_path = try w.path("changed-release.program");
    try w.write(changed_path, try program.encode(w.arena, changed_release));
    const result: Setups = .{
        .files = try assemble(w, "files", files),
        .v1 = try assemble(w, "env-v1", programs.v1),
        .v2 = try assemble(w, "env-v2", programs.v2),
        .missing = try assemble(w, "missing-migration", missing_path),
        .missing_library = try assemble(w, "missing-library-migration", no_library_path),
        .changed_release = try assemble(w, "changed-release", changed_path),
    };
    try identities(w, result);
    try rejectBadDigest(w, programs.v1);
    try rejectTamper(w, result.v1);
    try w.case("N2-AOT-01", "isolated-prebuilt-template", "PASS");
    try w.case("N2-IMAGE-01", "code-bytes-signatures-identities", "PASS");
    return result;
}

fn fileProgram(w: *World) ![]const u8 {
    var author = try compiler.Builder.init(w.arena, "example.files", 1, 1);
    try author.addLibrary("files", try w.read(w.tools.managed));
    try author.addAsset("readme", "Installed through a capability library.\n");
    try author.addResource("readme", "README.txt");
    try author.addInstance("files", "files", 1);
    try author.bind("files", .asset, "readme");
    try author.bind("files", .resource, "readme");
    const path = try w.path("files.program");
    try w.write(path, try author.emit());
    return path;
}

fn sandbox(w: *World) !void {
    const repo = try std.json.Stringify.valueAlloc(w.arena, w.repo, .{});
    const tool = try std.json.Stringify.valueAlloc(w.arena, try w.temporary("compiler"), .{});
    const profile = try w.arena.print(
        "(version 1)\n(allow default)\n(deny file-read* (subpath {s}))\n" ++
            "(deny process-exec (require-all (require-not (literal {s})) " ++
            "(require-not (literal \"/usr/bin/codesign\"))))\n",
        .{ repo, tool },
    );
    try w.write(try w.temporary("assembly.sb"), profile);
    try w.write(try w.path("assembly.sb"), profile);
}

fn isolationControls(w: *World, repository_program: []const u8) !void {
    const profile = try w.temporary("assembly.sb");
    const output = try w.temporary("forbidden-repository-input");
    const denied = try w.run(&.{
        "/usr/bin/sandbox-exec", "-f",               profile,     try w.temporary("compiler"),
        "--program",             repository_program, "--runtime", try w.temporary("runtime"),
        "--out",                 output,
    }, false);
    try expect(std.mem.indexOf(u8, denied.stderr, "PermissionDenied") != null);
    try expect(!try w.exists(output));
    // A harmless negative control proves arbitrary child executables are blocked too.
    try w.command(&.{ "/usr/bin/sandbox-exec", "-f", profile, "/usr/bin/true" }, false);
}

fn assemble(w: *World, name: []const u8, model: []const u8) ![]const u8 {
    const input = try w.temporary(try w.arena.print("{s}.program", .{name}));
    const output = try w.temporary(try w.arena.print("setup-{s}", .{name}));
    try w.copy(model, input);
    try w.command(&.{
        "/usr/bin/sandbox-exec",     "-f",                       try w.temporary("assembly.sb"),
        try w.temporary("compiler"), "--program",                input,
        "--runtime",                 try w.temporary("runtime"), "--out",
        output,
    }, true);
    try w.command(&.{ "/usr/bin/codesign", "--verify", "--strict", output }, true);
    try w.command(&.{
        w.tools.check_binary, "lint", "--target", "aarch64-macos", "--kind", "exe", output,
    }, true);
    try unchangedCode(w, output);
    const saved = try w.path(try w.arena.print("setup-{s}", .{name}));
    try w.copy(output, saved);
    return saved;
}

fn unchangedCode(w: *World, output: []const u8) !void {
    const original = try w.read(w.tools.runtime);
    const result = try w.read(output);
    try expect(std.mem.eql(u8, try textSection(original), try textSection(result)));
    const section = try program.image.productSection(result);
    const raw_digest = try program.decodeHex(w.arena, try w.hash(w.tools.runtime));
    try expect(std.mem.eql(u8, raw_digest, result[section.offset + 48 ..][0..32]));
    const model = try program.image.productFromExecutable(result);
    const decoded = try program.decode(w.arena, model);
    try expect(decoded.runtime_abi == 1);
}

fn identities(w: *World, setups: Setups) !void {
    try w.write(try w.path("identities.json"), try std.json.Stringify.valueAlloc(w.arena, .{
        .runtime_template = try w.hash(w.tools.runtime),
        .compiler = try w.hash(w.tools.compiler),
        .starlark = try w.hash(w.tools.starlark),
        .managed_library = try w.hash(w.tools.managed),
        .environment_v1_library = try w.hash(w.tools.env_v1),
        .environment_v2_library = try w.hash(w.tools.env_v2),
        .setup_files = try w.hash(setups.files),
        .setup_env_v1 = try w.hash(setups.v1),
        .setup_env_v2 = try w.hash(setups.v2),
    }, .{}));
    try expect(!std.mem.eql(u8, try w.hash(setups.files), try w.hash(setups.v1)));
    try w.expectFile(try w.temporary("runtime"), try w.read(w.tools.runtime));
}

fn rejectBadDigest(w: *World, source: []const u8) !void {
    var model = try program.decode(w.arena, try w.read(source));
    const libraries = try w.arena.dupe(program.Library, model.libraries);
    libraries[0].sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    model.libraries = libraries;
    const path = try w.temporary("bad-digest.program");
    // Deliberately bypass the encoder for this malformed machine-input vector.
    try w.write(path, try std.json.Stringify.valueAlloc(w.arena, model, .{}));
    const output = try w.temporary("bad-digest-setup");
    const result = try w.run(&.{
        try w.temporary("compiler"), "--program", path,   "--runtime",
        try w.temporary("runtime"),  "--out",     output,
    }, false);
    try expect(std.mem.indexOf(u8, result.stderr, "ProgramDigest") != null);
    try expect(!try w.exists(output));
}

fn rejectTamper(w: *World, source: []const u8) !void {
    const output = try w.path("tampered-setup");
    try w.copy(source, output);
    const bytes = try w.arena.dupe(u8, try w.read(output));
    const slot = try program.image.productSection(bytes);
    bytes[slot.offset + program.image.header_bytes] ^= 1;
    try w.write(output, bytes);
    try w.command(&.{ "/usr/bin/codesign", "--verify", "--strict", output }, false);
    const root = try w.path("tampered-root");
    try w.command(&.{ output, "install", "--root", root }, false);
    try expect(!try w.exists(root));
}

fn textSection(bytes: []const u8) ![]const u8 {
    const commands = try integer(u32, bytes, 16);
    if (commands > 128) return error.InvalidMachO;
    var offset: usize = 32;
    for (0..commands) |_| {
        const kind = try integer(u32, bytes, offset);
        const length = try integer(u32, bytes, offset + 4);
        if (length < 8 or offset > bytes.len or length > bytes.len - offset) {
            return error.InvalidMachO;
        }
        if (kind == 0x19) {
            if (length < 72) return error.InvalidMachO;
            const count = try integer(u32, bytes, offset + 64);
            if (count > 256 or count > (length - 72) / 80) return error.InvalidMachO;
            for (0..count) |index| {
                const section = offset + 72 + index * 80;
                if (!std.mem.startsWith(u8, bytes[section..][0..16], "__text\x00")) continue;
                if (!std.mem.startsWith(u8, bytes[section + 16 ..][0..16], "__TEXT\x00")) continue;
                const size = try integer(u64, bytes, section + 40);
                const start = try integer(u32, bytes, section + 48);
                if (start > bytes.len or size > bytes.len - start) return error.InvalidMachO;
                const end = std.math.cast(usize, start + size) orelse return error.InvalidMachO;
                return bytes[start..end];
            }
        }
        offset += length;
    }
    return error.InvalidMachO;
}

fn integer(comptime T: type, bytes: []const u8, offset: usize) !T {
    if (offset > bytes.len or @sizeOf(T) > bytes.len - offset) return error.InvalidMachO;
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
