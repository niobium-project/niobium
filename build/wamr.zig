//! Pinned classic interpreter integration; no system WAMR installation is consulted.
const std = @import("std");

pub fn attach(b: *std.Build, module: *std.Build.Module, source: std.Build.LazyPath) void {
    const target = module.resolved_target.?.result;
    std.debug.assert(target.os.tag == .macos);
    std.debug.assert(target.cpu.arch == .aarch64);
    module.link_libc = true;
    for (includes) |path| module.addIncludePath(source.path(b, path));
    module.addIncludePath(b.path("third_party/wamr"));
    module.addCSourceFiles(.{ .root = source, .files = sources, .flags = flags });
    module.addCSourceFiles(.{
        .files = &.{"third_party/wamr/host.c"},
        .flags = flags,
    });
}

const includes: []const []const u8 = &.{
    "core/iwasm/include",          "core/iwasm/common",            "core/iwasm/interpreter",
    "core/shared/platform/darwin", "core/shared/platform/include", "core/shared/mem-alloc",
    "core/shared/utils",
};

const flags: []const []const u8 = &.{
    "-std=gnu99",
    "-fno-strict-aliasing",
    "-Wno-unused-parameter",
    "-DBH_PLATFORM_DARWIN",
    "-DBUILD_TARGET_AARCH64",
    "-DBH_MALLOC=wasm_runtime_malloc",
    "-DBH_FREE=wasm_runtime_free",
    "-DWASM_ENABLE_INTERP=1",
    "-DWASM_ENABLE_FAST_INTERP=0",
    "-DWASM_ENABLE_INSTRUCTION_METERING=1",
    "-DWASM_ENABLE_AOT=0",
    "-DWASM_ENABLE_JIT=0",
    "-DWASM_ENABLE_FAST_JIT=0",
    "-DWASM_ENABLE_LIBC_WASI=0",
    "-DWASM_ENABLE_LIBC_BUILTIN=0",
    "-DWASM_ENABLE_LIB_PTHREAD=0",
    "-DWASM_ENABLE_LIB_WASI_THREADS=0",
    "-DWASM_ENABLE_THREAD_MGR=0",
    "-DWASM_ENABLE_SHARED_MEMORY=0",
    "-DWASM_ENABLE_MULTI_MODULE=0",
    "-DWASM_ENABLE_SIMD=0",
    "-DWASM_ENABLE_REF_TYPES=0",
    "-DWASM_ENABLE_GC=0",
    "-DWASM_ENABLE_BULK_MEMORY=1",
    "-DWASM_ENABLE_MEMORY64=0",
    "-DWASM_ENABLE_MULTI_MEMORY=0",
    "-DWASM_ENABLE_LOG=0",
    "-DWASM_DISABLE_HW_BOUND_CHECK=1",
    "-DWASM_DISABLE_STACK_HW_BOUND_CHECK=1",
    "-DWASM_DISABLE_APP_ENTRY=1",
    "-DWASM_HAVE_MREMAP=0",
    "-DWASM_CPU_SUPPORTS_UNALIGNED_ADDR_ACCESS=0",
};

const sources: []const []const u8 = &.{
    "core/shared/platform/darwin/platform_init.c",
    "core/shared/platform/common/posix/posix_blocking_op.c",
    "core/shared/platform/common/posix/posix_time.c",
    "core/shared/platform/common/posix/posix_malloc.c",
    "core/shared/platform/common/posix/posix_thread.c",
    "core/shared/platform/common/posix/posix_memmap.c",
    "core/shared/platform/common/posix/posix_sleep.c",
    "core/shared/platform/common/memory/mremap.c",
    "core/shared/mem-alloc/mem_alloc.c",
    "core/shared/mem-alloc/ems/ems_gc.c",
    "core/shared/mem-alloc/ems/ems_hmu.c",
    "core/shared/mem-alloc/ems/ems_alloc.c",
    "core/shared/mem-alloc/ems/ems_kfc.c",
    "core/shared/utils/bh_leb128.c",
    "core/shared/utils/bh_hashmap.c",
    "core/shared/utils/bh_common.c",
    "core/shared/utils/bh_list.c",
    "core/shared/utils/bh_log.c",
    "core/shared/utils/bh_assert.c",
    "core/shared/utils/bh_vector.c",
    "core/shared/utils/bh_bitmap.c",
    "core/shared/utils/bh_queue.c",
    "core/shared/utils/runtime_timer.c",
    "core/iwasm/common/wasm_c_api.c",
    "core/iwasm/common/wasm_loader_common.c",
    "core/iwasm/common/wasm_blocking_op.c",
    "core/iwasm/common/wasm_memory.c",
    "core/iwasm/common/wasm_shared_memory.c",
    "core/iwasm/common/wasm_exec_env.c",
    "core/iwasm/common/wasm_native.c",
    "core/iwasm/common/wasm_runtime_common.c",
    "core/iwasm/common/arch/invokeNative_aarch64.s",
    "core/iwasm/interpreter/wasm_loader.c",
    "core/iwasm/interpreter/wasm_runtime.c",
    "core/iwasm/interpreter/wasm_interp_classic.c",
};

/// Compile a guest using only the public C ABI and the pinned Zig toolchain.
pub fn guest(
    b: *std.Build,
    name: []const u8,
    path: []const u8,
    definitions: []const []const u8,
) *std.Build.Step.Compile {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const module = b.createModule(.{ .target = target, .optimize = .small });
    module.addIncludePath(b.path("api/c"));
    module.addCSourceFiles(.{
        .files = &.{path},
        .flags = definitions,
    });
    const artifact = b.addExecutable(.{ .name = name, .root_module = module });
    artifact.entry = .disabled;
    artifact.export_memory = true;
    artifact.initial_memory = 256 << 10;
    artifact.max_memory = 1 << 20;
    artifact.stack_size = 32 << 10;
    return artifact;
}

/// Embed freshly compiled examples in the independent host conformance executable.
pub fn fixtures(b: *std.Build) *std.Build.Module {
    const files = b.addWriteFiles();
    const source = files.add("fixtures.zig",
        \\pub const managed = @embedFile("managed.wasm");
        \\pub const optional = @embedFile("optional.wasm");
        \\pub const snapshot = @embedFile("snapshot.wasm");
        \\pub const zig_managed = @embedFile("zig-managed.wasm");
        \\pub const env_v1 = @embedFile("env-v1.wasm");
        \\pub const env_v2 = @embedFile("env-v2.wasm");
        \\pub const bad = .{
        \\    @embedFile("bad-1.wasm"), @embedFile("bad-2.wasm"),
        \\    @embedFile("bad-3.wasm"), @embedFile("bad-4.wasm"),
        \\    @embedFile("bad-5.wasm"), @embedFile("bad-6.wasm"),
        \\    @embedFile("bad-7.wasm"), @embedFile("bad-8.wasm"),
        \\    @embedFile("bad-9.wasm"), @embedFile("bad-10.wasm"),
        \\    @embedFile("bad-11.wasm"), @embedFile("bad-12.wasm"),
        \\};
    );
    const managed = guest(b, "managed", "examples/aot-libraries/managed-files.c", &.{});
    const managed_path = files.addCopyFile(managed.getEmittedBin(), "managed.wasm");
    _ = managed_path;
    const snapshot = guest(b, "snapshot", "examples/aot-libraries/state-snapshot.c", &.{});
    const snapshot_path = files.addCopyFile(snapshot.getEmittedBin(), "snapshot.wasm");
    _ = snapshot_path;
    const optional = guest(b, "optional", "examples/aot-libraries/optional-files.c", &.{});
    const optional_path = files.addCopyFile(optional.getEmittedBin(), "optional.wasm");
    _ = optional_path;
    const zig_path = files.addCopyFile(zigGuest(b).getEmittedBin(), "zig-managed.wasm");
    _ = zig_path;
    for (1..3) |version| {
        const name = b.fmt("env-v{d}", .{version});
        const definitions = &.{b.fmt("-DENV_VERSION={d}", .{version})};
        const artifact = guest(b, name, "examples/aot-libraries/generated-env.c", definitions);
        const path = files.addCopyFile(artifact.getEmittedBin(), b.fmt("{s}.wasm", .{name}));
        _ = path;
    }
    for (1..13) |index| {
        const name = b.fmt("bad-{d}", .{index});
        const definitions = &.{b.fmt("-DNEGATIVE_CASE={d}", .{index})};
        const artifact = guest(b, name, "examples/aot-libraries/negative.c", definitions);
        const path = files.addCopyFile(artifact.getEmittedBin(), b.fmt("{s}.wasm", .{name}));
        _ = path;
    }
    return b.createModule(.{ .root_source_file = source, .target = b.graph.host });
}

fn zigGuest(b: *std.Build) *std.Build.Step.Compile {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const sdk = b.createModule(.{
        .root_source_file = b.path("libs/capability_sdk/root.zig"),
        .target = target,
        .optimize = .small,
    });
    const module = b.createModule(.{
        .root_source_file = b.path("examples/aot-libraries/managed-files.zig"),
        .target = target,
        .optimize = .small,
    });
    module.addImport("capability_sdk", sdk);
    module.export_symbol_names = &.{"nb_plan_v1"};
    const artifact = b.addExecutable(.{ .name = "zig-managed", .root_module = module });
    artifact.entry = .disabled;
    artifact.export_memory = true;
    artifact.initial_memory = 256 << 10;
    artifact.max_memory = 1 << 20;
    artifact.stack_size = 128 << 10;
    return artifact;
}
