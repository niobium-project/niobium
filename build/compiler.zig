//! Build-time authoring tools. This graph never becomes a runtime dependency.

const std = @import("std");
const graph_mod = @import("graph.zig");

const Compile = std.Build.Step.Compile;
pub const Artifacts = struct {
    compiler: *Compile,
    library: *Compile,
    author_zig: *Compile,
    author_c: *Compile,
    starlark: std.Build.LazyPath,
    tests: *std.Build.Step,
};

pub fn add(b: *std.Build, graph: *const graph_mod.Graph) Artifacts {
    const compiler = b.addExecutable(.{
        .name = "niobium-compiler",
        .root_module = graph.root("apps/compiler/main.zig", &.{
            "compiler", "contracts", "program",
        }),
    });
    const library = b.addLibrary(.{
        .name = "niobium_compiler",
        .linkage = .static,
        .root_module = graph.root("apps/libcompiler/root.zig", &.{ "compiler", "contracts" }),
    });
    const author_zig = b.addExecutable(.{
        .name = "author-zig",
        .root_module = graph.root("examples/aot/author.zig", &.{ "compiler", "contracts" }),
    });
    const author_c = cExample(b, graph, library);
    const go_build = goCommand(b, library);
    go_build.addArgs(&.{ "build", "-trimpath", "-buildvcs=false", "-mod=readonly", "-o" });
    const starlark = go_build.addOutputFileArg("niobium-starlark");
    go_build.addArg(".");
    const tests = b.step("aot-authoring-test", "Compiler authoring and Starlark conformance");
    const go_test = goCommand(b, library);
    go_test.addArgs(&.{ "test", "-mod=readonly", "-count=1", "./..." });
    tests.dependOn(&go_test.step);
    for ([_][]const u8{ "apps/libcompiler/root.zig", "apps/compiler/main.zig" }) |source| {
        const suite = b.addTest(.{
            .root_module = graph.root(source, &.{ "compiler", "contracts", "program" }),
        });
        tests.dependOn(&b.addRunArtifact(suite).step);
    }
    return .{
        .compiler = compiler,
        .library = library,
        .author_zig = author_zig,
        .author_c = author_c,
        .starlark = starlark,
        .tests = tests,
    };
}

fn cExample(b: *std.Build, graph: *const graph_mod.Graph, library: *Compile) *Compile {
    const module = b.createModule(.{
        .target = graph.config.target,
        .optimize = graph.config.optimize,
        .link_libc = true,
    });
    module.addIncludePath(b.path("api/c"));
    module.addCSourceFile(.{
        .file = b.path("examples/aot/author.c"),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" },
    });
    module.linkLibrary(library);
    return b.addExecutable(.{ .name = "author-c", .root_module = module });
}

fn goCommand(b: *std.Build, library: *Compile) *std.Build.Step.Run {
    const run = b.addSystemCommand(&.{"env"});
    const target = library.rootModuleTarget();
    if (target.os.tag == .macos) {
        const minimum = target.os.version_range.semver.min;
        run.setEnvironmentVariable("MACOSX_DEPLOYMENT_TARGET", b.fmt("{d}.{d}.{d}", .{
            minimum.major, minimum.minor, minimum.patch,
        }));
    }
    run.addPrefixedDirectoryArg("CGO_LDFLAGS=-L", library.getEmittedBinDirectory());
    run.addArgs(&.{ "CGO_ENABLED=1", "GOPROXY=https://proxy.golang.org,direct", "go" });
    run.setCwd(b.path("apps/starlark"));
    run.addFileInput(library.getEmittedBin());
    run.addFileInput(b.path("api/c/compiler.h"));
    for ([_][]const u8{
        "go.mod", "go.sum", "author.go", "builtins.go", "main.go", "main_test.go",
    }) |file| run.addFileInput(b.path(b.fmt("apps/starlark/{s}", .{file})));
    return run;
}
