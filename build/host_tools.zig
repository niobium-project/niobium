//! Rust and Go for build and test steps. The pin file is `.zig/toolchains.zon`.
//! Example and VM steps do not depend on installation.

const std = @import("std");
const commands = @import("commands.zig");

const manifest = ".zig/toolchains.zon";
const root = ".cache/tools";
const pins = @import("../.zig/toolchains.zon");

comptime {
    if (!std.mem.eql(u8, pins.tools[1].id, "go")) @compileError("go is the second toolchain pin");
}

/// `go` as seen from `apps/compiler/starlark`, where the CGO launcher runs.
pub fn goBinary(b: *std.Build) []const u8 {
    const version = pins.tools[1].version;
    const ext = if (b.graph.host.result.os.tag == .windows) ".exe" else "";
    return b.fmt("../../../.cache/tools/go/{s}/bin/go{s}", .{ version, ext });
}

pub const Tools = struct {
    exe: *std.Build.Step.Compile,
    install: *std.Build.Step,

    pub fn cargo(self: Tools, b: *std.Build) *std.Build.Step.Run {
        return self.launch(b, "cargo");
    }

    pub fn go(self: Tools, b: *std.Build) *std.Build.Step.Run {
        return self.launch(b, "go");
    }

    pub fn require(self: Tools, b: *std.Build, name: []const u8, hint: []const u8) *std.Build.Step {
        const run = self.invoke(b, "require");
        run.addArgs(&.{ "--name", name, "--hint", hint });
        return &run.step;
    }

    fn launch(self: Tools, b: *std.Build, tool: []const u8) *std.Build.Step.Run {
        const run = self.invoke(b, "run");
        run.addArgs(&.{ "--tool", tool, "--" });
        run.step.dependOn(self.install);
        return run;
    }

    fn invoke(self: Tools, b: *std.Build, command: []const u8) *std.Build.Step.Run {
        return start(b, self.exe, command);
    }
};

fn start(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    command: []const u8,
) *std.Build.Step.Run {
    const run = b.addRunArtifact(exe);
    run.setName(b.fmt("toolchain {s}", .{command}));
    run.setCwd(b.path("."));
    run.addArgs(&.{ "toolchain", command, "--root", root, "--manifest", manifest });
    run.addFileInput(b.path(manifest));
    run.has_side_effects = true;
    return run;
}

pub fn add(b: *std.Build, exe: *std.Build.Step.Compile) Tools {
    const install_run = start(b, exe, "install");
    const install = commands.step(
        b,
        "tools:install",
        "Install pinned Rust and Go into .cache/tools",
    );
    install.dependOn(&install_run.step);
    const doctor = start(b, exe, "doctor");
    const doctor_step = commands.step(b, "tools:doctor", "Check pinned Rust and Go");
    doctor_step.dependOn(&doctor.step);
    return .{ .exe = exe, .install = install };
}
