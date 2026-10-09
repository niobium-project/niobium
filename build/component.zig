//! Bounded Component Model qualification with shared source and execution provenance.
const std = @import("std");
const commands = @import("commands.zig");
const Compile = std.Build.Step.Compile;
const toolchain = @import("component_tools.zig");
const graph_mod = @import("graph.zig");
const cpu = @import("component_cpu.zig");
pub const Inputs = struct {
    host: @import("host_tools.zig").Tools,
    wasm_tools: std.Build.LazyPath,
    wit_bindgen: std.Build.LazyPath,
    wasi_sysroot: std.Build.LazyPath,
    core: *std.Build.Module,
    program: *std.Build.Module,
    contracts: *std.Build.Module,
    publication: *const graph_mod.Graph,
};
pub const Artifacts = struct {
    step: *std.Build.Step,
    worker: *Compile,
    engine: *std.Build.Module,
    library: std.Build.LazyPath,
    cpu_provenance: std.Build.LazyPath,
    engine_build_log: std.Build.LazyPath,
    c_guest: std.Build.LazyPath,
    rust_guest: std.Build.LazyPath,
    caller: *Compile,
    reference_guest: std.Build.LazyPath,
    reference_guest_v2: std.Build.LazyPath,
    files_guest: std.Build.LazyPath,
};

pub fn add(b: *std.Build, inputs: Inputs) Artifacts {
    const native_build = native(b, inputs.host);
    const library = native_build.library;
    const engine = b.createModule(.{
        .root_source_file = b.path("third_party/wasmtime/session.zig"),
        .target = inputs.publication.config.target,
        .optimize = .safe,
        .link_libc = true,
    });
    engine.addObjectFile(library);
    attachNative(engine);
    const worker_module = b.createModule(.{
        .root_source_file = b.path("tests/component/worker.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .link_libc = true,
    });
    worker_module.addImport("component_engine", engine);
    const worker = b.addExecutable(.{ .name = "component-worker", .root_module = worker_module });
    const c_build = cGuest(b, inputs);
    const c_guest = c_build.binary;
    const rust_guest = rustGuest(b, inputs.host, inputs.wasm_tools);
    const provenance = b.createModule(.{
        .root_source_file = b.path("tests/component/provenance.zig"),
        .target = b.graph.host,
    });
    provenance.addImport("core", inputs.core);
    const module = b.createModule(.{
        .root_source_file = b.path("tests/component/main.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    });
    module.addImport("suite_provenance", provenance);
    const suite = b.addExecutable(.{ .name = "component-qualification", .root_module = module });
    const run = b.addRunArtifact(suite);
    run.setCwd(b.path("."));
    run.has_side_effects = true;
    run.addArtifactArg(worker);
    run.addFileArg(c_guest);
    run.addFileArg(rust_guest);
    for ([_][]const u8{
        "start",         "unauthorized", "wasi",       "threads", "memories",
        "grouped-types", "nested-types", "deep-types",
    }) |name| {
        const parse = std.Build.Step.Run.create(b, b.fmt("parse component {s}", .{name}));
        parse.addFileArg(toolchain.executable(b, inputs.wasm_tools, "wasm-tools"));
        parse.addArg("parse");
        parse.addFileArg(b.path(b.fmt("tests/component/{s}.wat", .{name})));
        parse.addArg("-o");
        run.addFileArg(parse.addOutputFileArg(b.fmt("{s}.wasm", .{name})));
    }
    run.addFileArg(c_build.log);
    const step = commands.step(b, "test:component", "WIT, Canonical ABI, and Pulley qualification");
    step.dependOn(&run.step);
    failureProvenance(b, inputs, suite, step);
    const production = ipc(b, inputs, engine, provenance, worker, rust_guest);
    step.dependOn(production.step);
    return .{
        .step = step,
        .worker = worker,
        .engine = engine,
        .library = library,
        .cpu_provenance = native_build.provenance,
        .engine_build_log = native_build.log,
        .c_guest = c_guest,
        .rust_guest = rust_guest,
        .caller = production.caller,
        .reference_guest = production.reference,
        .reference_guest_v2 = production.reference_v2,
        .files_guest = production.files,
    };
}

fn failureProvenance(
    b: *std.Build,
    inputs: Inputs,
    suite: *Compile,
    step: *std.Build.Step,
) void {
    const guard = b.addExecutable(.{
        .name = "component-provenance-check",
        .root_module = inputs.publication.root("tests/component/provenance_check.zig", &.{}),
    });
    const witness = b.addRunArtifact(guard);
    witness.addArtifactArg(suite);
    witness.addArg("tests/component/main.zig");
    witness.setCwd(b.path("."));
    witness.has_side_effects = true;
    step.dependOn(&witness.step);
}

const Native = struct {
    library: std.Build.LazyPath,
    provenance: std.Build.LazyPath,
    log: std.Build.LazyPath,
};

fn native(b: *std.Build, tools: @import("host_tools.zig").Tools) Native {
    const host = @import("publication.zig").baselineTarget(b).result;
    const triple = rustTarget(host);
    const cargo = tools.cargo(b);
    cargo.addArgs(&.{ "build", "-vv", "--release", "--locked", "--manifest-path" });
    cargo.addFileArg(b.path("third_party/wasmtime/adapter/Cargo.toml"));
    cargo.addArgs(&.{ "--target", triple });
    cargo.addArg("--target-dir");
    const target = cargo.addOutputDirectoryArg("wasmtime-target");
    for ([_][]const u8{
        "Cargo.lock", "lib.rs", "allocator.rs", "profile.rs", "type_budget.rs",
    }) |file| {
        cargo.addFileInput(b.path(b.fmt("third_party/wasmtime/adapter/{s}", .{file})));
    }
    const name = if (host.os.tag == .windows and host.abi == .msvc)
        "niobium_wasmtime.lib"
    else
        "libniobium_wasmtime.a";
    return .{
        .library = target.path(b, b.fmt("{s}/release/{s}", .{ triple, name })),
        .provenance = cpu.engine(b, cargo, host, triple),
        .log = cargo.captureStdErr(.{ .basename = "engine-build.log" }),
    };
}

fn rustTarget(host: std.Target) []const u8 {
    return switch (host.os.tag) {
        .macos => "aarch64-apple-darwin",
        .linux => if (host.abi == .musl)
            "x86_64-unknown-linux-musl"
        else
            "x86_64-unknown-linux-gnu",
        .windows => if (host.abi == .msvc)
            "x86_64-pc-windows-msvc"
        else
            "x86_64-pc-windows-gnu",
        else => unreachable, // Caller requires a qualified host tool profile.
    };
}

const GuestBuild = struct { binary: std.Build.LazyPath, log: std.Build.LazyPath };

fn cGuest(b: *std.Build, inputs: Inputs) GuestBuild {
    const bindgen = std.Build.Step.Run.create(b, "generate standard C bindings");
    bindgen.addFileArg(toolchain.executable(b, inputs.wit_bindgen, "wit-bindgen"));
    bindgen.addArg("c");
    bindgen.addFileArg(b.path("api/wit/qualification/qualification.wit"));
    bindgen.addArg("--out-dir");
    const generated = bindgen.addOutputDirectoryArg("generated");
    const log = bindgen.captureStdErr(.{ .basename = "wit-bindgen.log" });
    const clang = b.addSystemCommand(
        &.{
            b.graph.zig_exe,
            "cc",
            "-target",
            "wasm32-wasi",
            "-Oz",
            "-nostdlib",
            "-Dabort=nb_guest_abort",
            "-isystem",
        },
    );
    clang.addDirectoryArg(inputs.wasi_sysroot.path(b, "include/wasm32-wasip1"));
    clang.addArg("-I");
    clang.addDirectoryArg(generated);
    clang.addFileArg(generated.path(b, "qualification.c"));
    clang.addFileArg(generated.path(b, "qualification_component_type.o"));
    clang.addFileArg(b.path("tests/component/guest.c"));
    clang.addFileArg(inputs.wasi_sysroot.path(b, "lib/wasm32-wasip1/libc.a"));
    clang.addArgs(&.{
        "-Wl,--no-entry", "-Wl,--max-memory=33554432", "-Wl,-z,stack-size=65536", "-o",
    });
    return .{
        .binary = componentize(b, inputs.wasm_tools, clang.addOutputFileArg("guest.core.wasm")),
        .log = log,
    };
}

fn rustGuest(
    b: *std.Build,
    tools: @import("host_tools.zig").Tools,
    tool: std.Build.LazyPath,
) std.Build.LazyPath {
    const cargo = tools.cargo(b);
    cargo.addArgs(&.{
        "build",    "--release",              "--locked",        "--quiet",
        "--target", "wasm32-unknown-unknown", "--manifest-path",
    });
    cpu.guest(cargo);
    cargo.addFileArg(b.path("tests/component/rust/Cargo.toml"));
    cargo.addFileInput(b.path("tests/component/rust/Cargo.lock"));
    cargo.addFileInput(b.path("tests/component/rust/guest.rs"));
    cargo.addFileInput(b.path("api/wit/qualification/qualification.wit"));
    cargo.addArg("--target-dir");
    const target = cargo.addOutputDirectoryArg("guest-target");
    const binary = "wasm32-unknown-unknown/release/niobium_component_consumer.wasm";
    return componentize(b, tool, target.path(b, binary));
}

fn componentize(
    b: *std.Build,
    tool: std.Build.LazyPath,
    source: std.Build.LazyPath,
) std.Build.LazyPath {
    const run = std.Build.Step.Run.create(b, "encode standard component");
    run.addFileArg(toolchain.executable(b, tool, "wasm-tools"));
    run.addArgs(&.{ "component", "new", "--merge-imports-based-on-semver=false" });
    run.addFileArg(source);
    run.addArg("-o");
    return run.addOutputFileArg("guest.wasm");
}

/// Platform libraries listed by the pinned upstream C API CMake configuration.
pub fn attachNative(module: *std.Build.Module) void {
    module.link_libc = true;
    switch (module.resolved_target.?.result.os.tag) {
        .windows => {
            for ([_][]const u8{
                "ws2_32",
                "advapi32",
                "userenv",
                "ntdll",
                "shell32",
                "ole32",
                "bcrypt",
            }) |name| {
                module.linkSystemLibrary(name, .{ .use_pkg_config = .no });
            }
            if (module.resolved_target.?.result.abi == .gnu) {
                module.linkSystemLibrary("unwind", .{ .use_pkg_config = .no });
            }
        },
        .linux => for ([_][]const u8{ "pthread", "dl", "m", "unwind" }) |name| {
            module.linkSystemLibrary(name, .{ .use_pkg_config = .no });
        },
        else => {},
    }
}

const Production = struct {
    step: *std.Build.Step,
    caller: *Compile,
    reference: std.Build.LazyPath,
    reference_v2: std.Build.LazyPath,
    files: std.Build.LazyPath,
};

fn ipc(
    b: *std.Build,
    inputs: Inputs,
    engine: *std.Build.Module,
    provenance: *std.Build.Module,
    qualifier: *Compile,
    qualifier_guest: std.Build.LazyPath,
) Production {
    const caller = productionWorker(b, inputs, engine);
    const module = b.createModule(.{
        .root_source_file = b.path("tests/component/ipc.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    });
    module.addImport("program", inputs.program);
    module.addImport("contracts", inputs.contracts);
    module.addImport("suite_provenance", provenance);
    const client = b.createModule(.{
        .root_source_file = b.path("libs/component_client/root.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    });
    client.addImport("program", inputs.program);
    client.addImport("contracts", inputs.contracts);
    module.addImport("component_client", client);
    const suite = b.addExecutable(.{ .name = "component-ipc", .root_module = module });
    const run = b.addRunArtifact(suite);
    run.setCwd(b.path("."));
    run.has_side_effects = true;
    run.addArtifactArg(caller);
    const reference = packageGuest(b, inputs.host, inputs.wasm_tools, .{
        .source = "tests/component/reference",
        .wit = "api/wit/reference/reference.wit",
        .binary = "niobium_reference_library.wasm",
    });
    run.addFileArg(reference);
    const parse = std.Build.Step.Run.create(b, "parse direct world component");
    parse.addFileArg(toolchain.executable(b, inputs.wasm_tools, "wasm-tools"));
    parse.addArg("parse");
    parse.addFileArg(b.path("tests/component/direct.wat"));
    parse.addArg("-o");
    run.addFileArg(parse.addOutputFileArg("direct.wasm"));
    const files = packageGuest(b, inputs.host, inputs.wasm_tools, .{
        .source = "libs/stdlib/files",
        .wit = "api/wit/files/files.wit",
        .binary = "niobium_stdlib_files.wasm",
    });
    run.addFileArg(files);
    const probe = b.addExecutable(.{
        .name = "component-client-probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/component/client_probe.zig"),
            .target = b.graph.host,
            .optimize = .safe,
        }),
    });
    run.addArtifactArg(probe);
    run.addArtifactArg(qualifier);
    run.addFileArg(qualifier_guest);
    const reference_v2 = packageGuest(b, inputs.host, inputs.wasm_tools, .{
        .source = "tests/component/reference",
        .wit = "api/wit/reference/reference.wit",
        .binary = "niobium_reference_library.wasm",
        .feature = "revision-two",
    });
    run.addFileArg(reference_v2);
    return .{
        .step = &run.step,
        .caller = caller,
        .reference = reference,
        .reference_v2 = reference_v2,
        .files = files,
    };
}

fn productionWorker(b: *std.Build, inputs: Inputs, engine: *std.Build.Module) *Compile {
    const worker_module = b.createModule(.{
        .root_source_file = b.path("libs/component_worker/root.zig"),
        .target = inputs.publication.config.target,
        .optimize = .safe,
    });
    worker_module.addImport("program", inputs.publication.get("program"));
    worker_module.addImport("contracts", inputs.publication.get("contracts"));
    worker_module.addImport("component_engine", engine);
    const app = b.createModule(.{
        .root_source_file = b.path("apps/compiler/worker/main.zig"),
        .target = inputs.publication.config.target,
        .optimize = .safe,
    });
    app.addImport("component_worker", worker_module);
    return b.addExecutable(.{ .name = "nb-component-worker", .root_module = app });
}

const Package = struct {
    source: []const u8,
    wit: []const u8,
    binary: []const u8,
    feature: ?[]const u8 = null,
};

fn packageGuest(
    b: *std.Build,
    tools: @import("host_tools.zig").Tools,
    tool: std.Build.LazyPath,
    package: Package,
) std.Build.LazyPath {
    // Standard bindgen reads an isolated WIT package with its versioned dependency closure.
    const workspace = b.addWriteFiles();
    const manifest = workspace.addCopyFile(
        b.path(b.fmt("{s}/Cargo.toml", .{package.source})),
        "Cargo.toml",
    );
    const sources = [_]std.Build.LazyPath{
        workspace.addCopyFile(b.path(b.fmt("{s}/Cargo.lock", .{package.source})), "Cargo.lock"),
        workspace.addCopyFile(b.path(b.fmt("{s}/guest.rs", .{package.source})), "guest.rs"),
        workspace.addCopyFile(b.path(package.wit), "wit/library.wit"),
        workspace.addCopyFile(
            b.path("api/wit/runtime/proposal.wit"),
            "wit/deps/runtime/proposal.wit",
        ),
    };
    const cargo = tools.cargo(b);
    cargo.addArgs(&.{
        "build",    "--release",              "--locked",        "--quiet",
        "--target", "wasm32-unknown-unknown", "--manifest-path",
    });
    cpu.guest(cargo);
    cargo.addFileArg(manifest);
    if (package.feature) |feature| cargo.addArgs(&.{ "--features", feature });
    for (sources) |source| cargo.addFileInput(source);
    cargo.addArg("--target-dir");
    const target = cargo.addOutputDirectoryArg("guest-target");
    return componentize(
        b,
        tool,
        target.path(b, b.fmt("wasm32-unknown-unknown/release/{s}", .{package.binary})),
    );
}
