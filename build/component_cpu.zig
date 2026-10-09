//! Published engine and author binaries use explicit code-generator CPU profiles.
const std = @import("std");
const publication = @import("publication.zig");
const EnvMap = std.process.Environ.Map;

const Profile = struct {
    rust_cpu: []const u8,
    rust_features: ?[]const u8 = null,
    c_compiler: []const u8,
    c_flags: []const u8,
};

fn profile(target: std.Target) Profile {
    std.debug.assert(target.cpu.arch == .aarch64 or target.cpu.arch == .x86_64);
    return switch (target.os.tag) {
        .macos => .{
            .rust_cpu = "apple-m1",
            .c_compiler = "/usr/bin/clang",
            .c_flags = "-mcpu=apple-m1",
        },
        .linux => .{
            .rust_cpu = "x86-64",
            .c_compiler = "/usr/bin/cc",
            .c_flags = "-march=x86-64 -mtune=generic",
        },
        .windows => .{
            .rust_cpu = "x86-64",
            .rust_features = "+cmpxchg16b,+sse3,+lahfsahf",
            .c_compiler = if (target.abi == .msvc) "cl.exe" else "gcc",
            .c_flags = if (target.abi == .msvc)
                ""
            else
                "-march=x86-64 -mtune=generic -mcx16 -msse3 -msahf",
        },
        else => unreachable, // Publication admits only the three qualified target profiles.
    };
}

pub fn engine(
    b: *std.Build,
    run: *std.Build.Step.Run,
    target: std.Target,
    triple: []const u8,
) std.Build.LazyPath {
    std.debug.assert(triple.len != 0);
    if (publication.nativeProfile(target)) |_| {
        const settings = profile(target);
        const flags = rustFlags(b, settings);
        engineEnvironment(
            b.allocator,
            run.getEnvMap(),
            settings,
            triple,
            flags,
        ) catch @panic("OOM");
    } else |_| {
        run.step.dependOn(&b.addFail("Unqualified native CPU/ABI publication profile").step);
    }
    return provenance(b, target, triple);
}

pub fn provenance(
    b: *std.Build,
    target: std.Target,
    triple: []const u8,
) std.Build.LazyPath {
    std.debug.assert(triple.len != 0);
    const native_profile = publication.nativeProfile(target) catch {
        return failedProvenance(b);
    };
    const settings = profile(target);
    const flags = rustFlags(b, settings);
    const bytes = std.json.Stringify.valueAlloc(b.allocator, .{
        .schema = 1,
        .native_cpu_profile = native_profile,
        .zig = .{
            .version = @import("builtin").zig_version_string,
            .target = target.zigTriple(b.allocator) catch @panic("OOM"),
            .cpu = "baseline",
            .cpu_model = target.cpu.model.name,
        },
        .rust_toolchain = "1.96.1",
        .rust_target = triple,
        .cargo_encoded_rustflags = flags,
        .rustc = "rustc (pinned cargo toolchain)",
        .rust_wrappers = "disabled",
        .native_c = settings,
        .cc_environment = "all cc-rs flag scopes cleared before fixed values",
        .author = .{
            .goenv = "off",
            .goexperiment = "",
            .clang_override_options = "unset",
            .goamd64 = "v1",
            .goarm64 = "v8.0",
            .cc = authorCompiler(b, target),
            .cgo_cflags = authorFlags(b, target),
            .cgo_cppflags = "",
            .cgo_fflags = "",
            .cgo_ldflags = "launcher-owned exact C ABI library directory",
        },
    }, .{ .whitespace = .indent_2 }) catch @panic("OOM");
    return b.addWriteFiles().add("engine-cpu.json", bytes);
}

fn failedProvenance(b: *std.Build) std.Build.LazyPath {
    const bytes = b.addWriteFiles();
    bytes.step.dependOn(&b.addFail("Unqualified native CPU/ABI publication profile").step);
    return bytes.add("engine-cpu.json", "{}");
}

fn rustFlags(b: *std.Build, settings: Profile) []const u8 {
    return if (settings.rust_features) |features|
        b.fmt("-C\x1ftarget-cpu={s}\x1f-C\x1ftarget-feature={s}", .{ settings.rust_cpu, features })
    else
        b.fmt("-C\x1ftarget-cpu={s}", .{settings.rust_cpu});
}

pub fn guest(run: *std.Build.Step.Run) void {
    rustEnvironment(run.getEnvMap(), "-C\x1ftarget-cpu=generic") catch @panic("OOM");
}

fn rustEnvironment(env: *EnvMap, flags: []const u8) std.mem.Allocator.Error!void {
    try env.put("CARGO_ENCODED_RUSTFLAGS", flags);
    try env.put("RUSTFLAGS", "");
    try env.put("RUSTC", "rustc");
    try env.put("RUSTUP_TOOLCHAIN", "1.96.1");
    try env.put("RUSTC_WRAPPER", "");
    try env.put("RUSTC_WORKSPACE_WRAPPER", "");
}

fn engineEnvironment(
    arena: std.mem.Allocator,
    env: *EnvMap,
    settings: Profile,
    triple: []const u8,
    flags: []const u8,
) std.mem.Allocator.Error!void {
    try rustEnvironment(env, flags);
    const normalized = try std.mem.replaceOwned(u8, arena, triple, "-", "_");
    defer arena.free(normalized);
    for ([_][]const u8{
        "CFLAGS", "CPPFLAGS", "CXXFLAGS", "CC", "CXX", "ARFLAGS", "AR", "RANLIB",
    }) |key| {
        const names = [_][]const u8{
            try arena.dupe(u8, key),
            try arena.print("HOST_{s}", .{key}),
            try arena.print("TARGET_{s}", .{key}),
            try arena.print("{s}_{s}", .{ key, triple }),
            try arena.print("{s}_{s}", .{ key, normalized }),
        };
        for (names) |name| {
            defer arena.free(name);
            const removed = env.swapRemove(name);
            _ = removed;
        }
    }
    try env.put("CC", settings.c_compiler);
    try env.put("CFLAGS", settings.c_flags);
    for ([_][]const u8{
        "CRATE_CC_NO_DEFAULTS",    "CC_FORCE_DISABLE",     "CC_SHELL_ESCAPED_FLAGS",
        "CC_KNOWN_WRAPPER_CUSTOM", "CCC_OVERRIDE_OPTIONS",
    }) |key| {
        const removed = env.swapRemove(key);
        _ = removed;
    }
    try env.put("CC_ENABLE_DEBUG_OUTPUT", "1");
}

fn authorCompiler(b: *std.Build, target: std.Target) []const u8 {
    if (target.os.tag == .windows) {
        // The pinned linker handles compiler_rt's COFF weak aliases correctly.
        return b.fmt("\"{s}\" cc -target x86_64-windows-gnu -mcpu=baseline", .{b.graph.zig_exe});
    }
    return profile(target).c_compiler;
}

pub fn author(b: *std.Build, run: *std.Build.Step.Run, target: std.Target) void {
    authorEnvironment(
        run.getEnvMap(),
        target,
        authorCompiler(b, target),
        authorFlags(b, target),
    ) catch @panic("OOM");
}

fn authorFlags(b: *std.Build, target: std.Target) []const u8 {
    const flags = if (target.os.tag == .windows)
        "-mcpu=baseline+cx16+sse3+sahf"
    else
        profile(target).c_flags;
    return b.fmt("-O2 -g {s}", .{flags});
}

fn authorEnvironment(
    env: *EnvMap,
    target: std.Target,
    compiler: []const u8,
    flags: []const u8,
) std.mem.Allocator.Error!void {
    const removed = env.swapRemove("CCC_OVERRIDE_OPTIONS");
    _ = removed;
    try env.put("GOENV", "off");
    try env.put("GOFLAGS", "");
    try env.put("GOEXPERIMENT", "");
    try env.put("GOAMD64", "v1");
    try env.put("GOARM64", "v8.0");
    try env.put("GOARCH", if (target.cpu.arch == .aarch64) "arm64" else "amd64");
    try env.put("GOOS", if (target.os.tag == .macos) "darwin" else @tagName(target.os.tag));
    try env.put("CC", compiler);
    try env.put("CXX", if (target.os.tag == .macos) "/usr/bin/clang++" else "c++");
    try env.put("CGO_CFLAGS", flags);
    try env.put("CGO_CXXFLAGS", flags);
    try env.put("CGO_CPPFLAGS", "");
    try env.put("CGO_FFLAGS", "");
    try env.put("CGO_LDFLAGS", "");
}

test "N2-CPU-01: engine replaces inherited CPU flags across every cc-rs scope" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env: EnvMap = .init(allocator);
    const keys = [_][]const u8{
        "CFLAGS",
        "HOST_CFLAGS",
        "TARGET_CFLAGS",
        "CFLAGS_x86_64-unknown-linux-gnu",
        "CFLAGS_x86_64_unknown_linux_gnu",
        "CC",
        "HOST_CC",
        "TARGET_CC",
        "CC_x86_64-unknown-linux-gnu",
        "CC_x86_64_unknown_linux_gnu",
        "RUSTFLAGS",
        "CARGO_ENCODED_RUSTFLAGS",
        "RUSTC_WRAPPER",
        "RUSTC_WORKSPACE_WRAPPER",
        "CRATE_CC_NO_DEFAULTS",
        "CC_FORCE_DISABLE",
        "CCC_OVERRIDE_OPTIONS",
    };
    for (keys) |key| try env.put(key, "host-specific-compiler -march=native");
    var target = @import("builtin").target;
    target.os.tag = .linux;
    target.cpu.arch = .x86_64;
    const flags = "-C\x1ftarget-cpu=x86-64";
    try engineEnvironment(allocator, &env, profile(target), "x86_64-unknown-linux-gnu", flags);
    try std.testing.expectEqualStrings(flags, env.get("CARGO_ENCODED_RUSTFLAGS").?);
    try std.testing.expectEqualStrings("", env.get("RUSTC_WRAPPER").?);
    try std.testing.expectEqualStrings("", env.get("RUSTC_WORKSPACE_WRAPPER").?);
    try std.testing.expectEqualStrings("/usr/bin/cc", env.get("CC").?);
    try std.testing.expectEqualStrings("-march=x86-64 -mtune=generic", env.get("CFLAGS").?);
    for (keys[1..5]) |key| try std.testing.expect(env.get(key) == null);
    for (keys[6..10]) |key| try std.testing.expect(env.get(key) == null);
    for (keys[14..]) |key| try std.testing.expect(env.get(key) == null);
}

test "N2-CPU-01: author clears Go environment and CGO feature overrides" {
    var env: EnvMap = .init(std.testing.allocator);
    defer env.deinit();
    const keys = [_][]const u8{
        "GOFLAGS",
        "GOENV",
        "GOAMD64",
        "GOARM64",
        "CC",
        "CGO_CFLAGS",
        "CGO_CXXFLAGS",
        "CGO_CPPFLAGS",
        "CGO_FFLAGS",
        "CGO_LDFLAGS",
        "GOEXPERIMENT",
        "CCC_OVERRIDE_OPTIONS",
    };
    for (keys) |key| try env.put(key, "host-specific");
    try authorEnvironment(&env, @import("builtin").target, "fixed-compiler", "fixed-flags");
    try std.testing.expectEqualStrings("off", env.get("GOENV").?);
    try std.testing.expectEqualStrings("v1", env.get("GOAMD64").?);
    try std.testing.expectEqualStrings("v8.0", env.get("GOARM64").?);
    try std.testing.expectEqualStrings("fixed-compiler", env.get("CC").?);
    try std.testing.expectEqualStrings("fixed-flags", env.get("CGO_CFLAGS").?);
    try std.testing.expectEqualStrings("fixed-flags", env.get("CGO_CXXFLAGS").?);
    try std.testing.expect(env.get("CCC_OVERRIDE_OPTIONS") == null);
    for ([_][]const u8{
        "GOFLAGS", "GOEXPERIMENT", "CGO_CPPFLAGS", "CGO_FFLAGS", "CGO_LDFLAGS",
    }) |key| {
        try std.testing.expectEqualStrings("", env.get(key).?);
    }
}
