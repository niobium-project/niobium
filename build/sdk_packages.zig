//! Explicit release archives use the same staged bytes as the installed SDK.
const std = @import("std");
const commands = @import("commands.zig");
const version = @import("../build.zig").version;
const manifest = @import("../build.zig.zon");

pub fn add(b: *std.Build, inputs: @import("delivery.zig").Inputs) void {
    cPackage(b, inputs.author_library);
    sourcePackage(b);
    runtimePackage(b, inputs);
}

fn cPackage(b: *std.Build, library: *std.Build.Step.Compile) void {
    const name = b.fmt("niobium-sdk-c-{s}-{s}", .{ version, targetName(b, library) });
    const files = b.addWriteFiles();
    copy(b, files, library.getEmittedBin(), name, b.fmt("lib/{s}", .{library.out_filename}));
    copy(b, files, b.path("api/c/compiler.h"), name, "include/niobium/compiler.h");
    copy(b, files, b.path("LICENSE"), name, "LICENSE");
    commands.step(b, "sdk:c", "Package the C authoring SDK")
        .dependOn(archive(b, files, name));
}

fn sourcePackage(b: *std.Build) void {
    const name = b.fmt("niobium-sdk-zig-{s}-source", .{version});
    const files = b.addWriteFiles();
    inline for (manifest.paths) |path| {
        if (comptime std.mem.eql(u8, path, "build.zig") or
            std.mem.eql(u8, path, "build.zig.zon") or std.mem.eql(u8, path, "LICENSE"))
        {
            copy(b, files, b.path(path), name, path);
        } else {
            // lint-allow(no-discard-call): the archive consumes the generated directory.
            _ = files.addCopyDirectory(b.path(path), b.fmt("{s}/{s}", .{ name, path }), .{});
        }
    }
    commands.step(b, "sdk:zig", "Package the Zig compiler.author source SDK")
        .dependOn(archive(b, files, name));
}

fn runtimePackage(b: *std.Build, inputs: @import("delivery.zig").Inputs) void {
    const name = b.fmt("niobium-runtime-{s}-{s}", .{ version, targetName(b, inputs.runtime) });
    const files = b.addWriteFiles();
    const executable = b.fmt("bin/{s}", .{inputs.runtime.out_filename});
    copy(b, files, inputs.runtime.getEmittedBin(), name, executable);
    copy(b, files, inputs.metadata, name, "share/niobium/runtime-package.json");
    copy(b, files, inputs.cpu_provenance, name, "share/niobium/provenance/cpu.json");
    copy(b, files, inputs.engine_build_log, name, "share/niobium/provenance/engine-build.log");
    copy(b, files, b.path("LICENSE"), name, "LICENSE");
    const license = b.path("third_party/wasmtime/LICENSE");
    copy(b, files, license, name, "share/niobium/licenses/wasmtime.txt");
    for ([_][]const u8{ "PROVENANCE.md", "adapter/Cargo.lock", "toolchain.zon" }) |path| {
        const source = b.path(b.fmt("third_party/wasmtime/{s}", .{path}));
        const destination = b.fmt("share/niobium/provenance/wasmtime/{s}", .{path});
        copy(b, files, source, name, destination);
    }
    const step = commands.step(b, "runtime:package", "Package the qualified precompiled runtime");
    step.dependOn(inputs.binary_check);
    step.dependOn(archive(b, files, name));
}

fn copy(
    b: *std.Build,
    files: *std.Build.Step.WriteFile,
    source: std.Build.LazyPath,
    name: []const u8,
    destination: []const u8,
) void {
    // lint-allow(no-discard-call): the archive consumes the generated directory.
    _ = files.addCopyFile(source, b.fmt("{s}/{s}", .{ name, destination }));
}

fn archive(b: *std.Build, files: *std.Build.Step.WriteFile, name: []const u8) *std.Build.Step {
    const tar = std.Build.Step.Run.create(b, b.fmt("package {s}", .{name}));
    tar.addFileArg(b.findProgramLazy(.{ .names = &.{"tar"} }));
    tar.addArg("-czf");
    const filename = b.fmt("{s}.tar.gz", .{name});
    const output = tar.addOutputFileArg(filename);
    tar.addArgs(&.{
        "--exclude=.zig-cache",
        "--exclude=.cache",
        "--exclude=zig-out",
        "--exclude=target",
        "--exclude=node_modules",
        "--exclude=__pycache__",
        "-C",
    });
    tar.addDirectoryArg(files.getDirectory());
    tar.addArg(name);
    return &b.addInstallFile(output, b.fmt("packages/{s}", .{filename})).step;
}

fn targetName(b: *std.Build, artifact: *std.Build.Step.Compile) []const u8 {
    const target = artifact.rootModuleTarget();
    return b.fmt("{s}-{s}-{s}", .{
        @tagName(target.cpu.arch), @tagName(target.os.tag), @tagName(target.abi),
    });
}
