//! `hooks:install`, `hooks:pre-commit`, and `hooks:pre-push`.

const std = @import("std");

pub fn add(b: *std.Build, check_commits: *std.Build.Step.Compile) void {
    const hooks = executable(b);
    const install = run(b, hooks, "install");
    const inputs = [_][]const u8{
        ".githooks/posix/pre-commit",
        ".githooks/posix/commit-msg",
        ".githooks/posix/pre-push",
        ".githooks/windows/launch.sh",
        ".githooks/windows/pre-commit.cmd",
        ".githooks/windows/commit-msg.cmd",
        ".githooks/windows/pre-push.cmd",
    };
    for (inputs) |path| install.addFileInput(b.path(path));
    const installed = b.step("hooks:install", "Copy .githooks into .git/hooks");
    installed.dependOn(&install.step);

    const pre_commit = run(b, hooks, "pre-commit");
    pre_commit.addArg(b.graph.zig_exe);
    const commit = b.step("hooks:pre-commit", "Check zig fmt on staged Zig files");
    commit.dependOn(&pre_commit.step);

    const pre_push = run(b, hooks, "pre-push");
    pre_push.addArtifactArg(check_commits);
    const push = b.step("hooks:pre-push", "Check subjects that would be pushed");
    push.dependOn(&pre_push.step);
}

pub fn addTests(b: *std.Build, step: *std.Build.Step) void {
    const unit = b.addTest(.{
        .name = "git-hooks",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/git-hooks/main.zig"),
            .target = b.graph.host,
        }),
    });
    step.dependOn(&b.addRunArtifact(unit).step);
}

fn executable(b: *std.Build) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "nb-git-hooks",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/git-hooks/main.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
}

fn run(b: *std.Build, exe: *std.Build.Step.Compile, mode: []const u8) *std.Build.Step.Run {
    const step = b.addRunArtifact(exe);
    step.setName(b.fmt("hooks {s}", .{mode}));
    step.setCwd(b.path("."));
    step.addArg(mode);
    step.stdio = .inherit;
    step.has_side_effects = true;
    return step;
}
