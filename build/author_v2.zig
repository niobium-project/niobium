//! Version-two author frontends share compiler.author.Builder through the public C ABI.
const std = @import("std");
const graph_mod = @import("graph.zig");
pub const Artifacts = struct {
    library: *std.Build.Step.Compile,
    tests: *std.Build.Step,
    starlark: std.Build.LazyPath,
    parity: *std.Build.Step.Run,
    native: *std.Build.Step.Compile,
    c_author: *std.Build.Step.Compile,
};
pub fn add(b: *std.Build, graph: *const graph_mod.Graph) Artifacts {
    const library = b.addLibrary(.{
        .name = "niobium_compiler_v2",
        .linkage = .static,
        .root_module = graph.root("apps/libcompiler/v2.zig", &.{ "compiler", "contracts" }),
    });
    library.bundle_compiler_rt = true;
    const suite = b.addTest(.{
        .root_module = graph.root("apps/libcompiler/v2.zig", &.{ "compiler", "contracts" }),
    });
    const run = b.addRunArtifact(suite);
    run.has_side_effects = true;
    const tests = b.step("author-v2-test", "Typed native and C authoring contract conformance");
    tests.dependOn(&run.step);
    const launcher = b.addExecutable(.{
        .name = "go-author-build",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/starlark/build.zig"),
            .target = b.graph.host,
            .optimize = .safe,
        }),
    });
    const go_flags = &.{ "-trimpath", "-buildvcs=false", "-mod=readonly" };
    const go_build = goCommand(b, launcher, library);
    go_build.addArg("build");
    go_build.addArgs(go_flags);
    go_build.addArg("-o");
    const starlark = go_build.addOutputFileArg(if (b.graph.host.result.os.tag == .windows)
        "niobium-starlark-v2.exe"
    else
        "niobium-starlark-v2");
    go_build.addArg("./v2");
    const go_test = goCommand(b, launcher, library);
    // Share the completed cold CGO build; tests still execute on every invocation.
    go_test.step.dependOn(&go_build.step);
    go_test.addArg("test");
    go_test.addArgs(go_flags);
    go_test.addArgs(&.{ "-count=1", "-timeout=60s", "-v", "./v2" });
    tests.dependOn(&go_test.step);
    tests.dependOn(&go_build.step);
    const parity = paritySuite(b, graph, library, starlark);
    tests.dependOn(&parity.run.step);
    return .{
        .library = library,
        .tests = tests,
        .starlark = starlark,
        .parity = parity.run,
        .native = parity.native,
        .c_author = parity.c_author,
    };
}

fn goCommand(
    b: *std.Build,
    launcher: *std.Build.Step.Compile,
    library: *std.Build.Step.Compile,
) *std.Build.Step.Run {
    const run = b.addRunArtifact(launcher);
    run.setCwd(b.path("apps/starlark"));
    const target = library.rootModuleTarget();
    if (target.os.tag == .macos) {
        const minimum = target.os.version_range.semver.min;
        run.setEnvironmentVariable("MACOSX_DEPLOYMENT_TARGET", b.fmt("{d}.{d}.{d}", .{
            minimum.major, minimum.minor, minimum.patch,
        }));
    }
    if (target.os.tag == .windows) {
        // The pinned linker handles compiler_rt's COFF weak aliases correctly.
        run.setEnvironmentVariable("CC", b.fmt(
            "\"{s}\" cc -target x86_64-windows-gnu",
            .{b.graph.zig_exe},
        ));
    }
    run.addFileArg(library.getEmittedBin());
    run.addFileInput(b.path("api/c/compiler_v2.h"));
    for ([_][]const u8{
        "go.mod",
        "go.sum",
        "v2/author.go",
        "v2/values.go",
        "v2/builtins.go",
        "v2/main.go",
        "v2/main_test.go",
    }) |file| {
        run.addFileInput(b.path(b.fmt("apps/starlark/{s}", .{file})));
    }
    return run;
}

const Parity = struct {
    run: *std.Build.Step.Run,
    native: *std.Build.Step.Compile,
    c_author: *std.Build.Step.Compile,
};
fn paritySuite(
    b: *std.Build,
    graph: *const graph_mod.Graph,
    library: *std.Build.Step.Compile,
    starlark: std.Build.LazyPath,
) Parity {
    const native = b.addExecutable(.{
        .name = "author-v2-native",
        .root_module = graph.root("tests/author/author.zig", &.{"compiler"}),
    });
    const c_module = b.createModule(
        .{ .target = b.graph.host, .optimize = .safe, .link_libc = true },
    );
    c_module.addIncludePath(b.path("api/c"));
    c_module.addCSourceFile(
        .{
            .file = b.path("tests/author/author.c"),
            .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" },
        },
    );
    c_module.linkLibrary(library);
    const c_author = b.addExecutable(.{ .name = "author-v2-c", .root_module = c_module });
    const module = graph.root("tests/author/main.zig", &.{"program"});
    const provenance = graph.root("tests/aot/provenance.zig", &.{"core"});
    module.addImport("suite_provenance", provenance);
    const suite = b.addExecutable(.{ .name = "author-v2-parity", .root_module = module });
    const run = b.addRunArtifact(suite);
    run.setCwd(b.path("."));
    run.has_side_effects = true;
    run.addArtifactArg(native);
    run.addArtifactArg(c_author);
    run.addFileArg(starlark);
    run.addFileArg(b.path("tests/author/author.star"));
    run.addFileInput(b.path("tests/author/types.star"));
    return .{ .run = run, .native = native, .c_author = c_author };
}
