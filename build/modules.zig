//! Single source of truth for the module graph and its dependency direction.
//! Pure data: imported by build.zig and by tools/check, so it must not depend on std.Build.

pub const Layer = enum(u8) {
    core = 0,
    contracts = 1,
    platform = 2,
    service = 3,
    flow = 4,
    orchestration = 5,
    ui_base = 10,
    ui_kit = 11,
    ui_screens = 12,
    ui_render = 13,
    ui_backend = 14,
    third_party = 20,
};

pub const CLibrary = enum { none, stb_truetype, zstd_compress, wamr, access };
pub const Phase = enum { shared, build_time, install_time, policy };

pub const ModuleSpec = struct {
    name: []const u8,
    root: []const u8,
    layer: Layer,
    imports: []const []const u8,
    c_library: CLibrary = .none,
    /// Linked when the target is macOS (system frameworks referenced by `extern` declarations).
    macos_frameworks: []const []const u8 = &.{},
    /// System libraries linked per target OS (`extern "lib"` declarations).
    macos_libraries: []const []const u8 = &.{},
    windows_libraries: []const []const u8 = &.{},
    /// Generated modules have no source root in the repository.
    generated: bool = false,
    phase: Phase = .shared,
    /// A declared PoC profile, not a claim about other platform implementations.
    macos_arm64_only: bool = false,
};

pub const specs = [_]ModuleSpec{
    .{ .name = "core", .root = "libs/core/root.zig", .layer = .core, .imports = &.{} },
    .{
        .name = "contracts",
        .root = "libs/contracts/root.zig",
        .layer = .contracts,
        .imports = &.{"core"},
    },
    .{
        .name = "program",
        .root = "libs/program/root.zig",
        .layer = .service,
        .imports = &.{ "core", "contracts", "access_policy", "content" },
    },
    .{
        .name = "wasm_profile",
        .root = "libs/wasm_profile/root.zig",
        .layer = .service,
        .imports = &.{"contracts"},
    },
    .{
        .name = "tar",
        .root = "libs/tar/root.zig",
        .layer = .core,
        .imports = &.{},
    },
    .{
        .name = "content",
        .root = "libs/content/root.zig",
        .layer = .service,
        .imports = &.{ "contracts", "tar" },
    },
    .{
        .name = "image",
        .root = "libs/image/root.zig",
        .layer = .service,
        .imports = &.{ "contracts", "content" },
    },
    .{
        .name = "access_policy",
        .root = "libs/access/contract/root.zig",
        .layer = .contracts,
        .imports = &.{},
    },
    .{
        .name = "access",
        .root = "libs/access/root.zig",
        .layer = .service,
        .imports = &.{ "contracts", "platform", "access_policy" },
        .c_library = .access,
        .windows_libraries = &.{ "advapi32", "kernel32", "ntdll" },
    },
    .{
        .name = "component_engine",
        .root = "third_party/wasmtime/session.zig",
        .layer = .third_party,
        .imports = &.{},
    },
    .{
        .name = "component_worker",
        .root = "libs/component_worker/root.zig",
        .layer = .flow,
        .imports = &.{ "program", "contracts", "component_engine" },
    },
    .{
        .name = "component_client",
        .root = "libs/component_client/root.zig",
        .layer = .flow,
        .imports = &.{ "program", "contracts" },
    },
    .{
        .name = "host_primitives",
        .root = "libs/host_primitives/root.zig",
        .layer = .service,
        .imports = &.{"program"},
    },
    .{
        .name = "kernel",
        .root = "libs/kernel/root.zig",
        .layer = .orchestration,
        .imports = &.{ "contracts", "program", "content", "access", "access_policy", "platform" },
        .phase = .install_time,
    },
    .{
        .name = "evaluator",
        .root = "libs/evaluator/root.zig",
        .layer = .orchestration,
        .imports = &.{
            "contracts",       "program",       "content", "kernel", "component_client",
            "host_primitives", "access_policy",
        },
        .phase = .install_time,
    },
    .{
        .name = "runtime_process",
        .root = "apps/runtime-v2/main.zig",
        .layer = .orchestration,
        .imports = &.{
            "image",            "program",  "contracts", "kernel", "evaluator", "host_primitives",
            "component_worker", "platform", "content",   "access",
        },
        .phase = .install_time,
    },
    .{
        .name = "capability_sdk",
        .root = "libs/capability_sdk/root.zig",
        .layer = .service,
        .imports = &.{},
    },
    .{
        .name = "compiler",
        .root = "libs/compiler/root.zig",
        .layer = .orchestration,
        .imports = &.{ "program", "contracts", "wasm_profile", "content", "image" },
        .phase = .build_time,
    },
    .{
        .name = "wasm_host",
        .root = "libs/wasm_host/root.zig",
        .layer = .service,
        .imports = &.{ "contracts", "wasm_profile", "wamr" },
        .phase = .install_time,
        .macos_arm64_only = true,
    },
    .{
        .name = "runtime",
        .root = "libs/runtime/root.zig",
        .layer = .orchestration,
        .imports = &.{ "program", "contracts", "platform", "wasm_host" },
        .phase = .install_time,
        .macos_arm64_only = true,
    },
    .{
        .name = "wamr",
        .root = "third_party/wamr/bindings.zig",
        .layer = .third_party,
        .imports = &.{},
        .c_library = .wamr,
        .phase = .install_time,
        .macos_arm64_only = true,
    },
    .{
        .name = "platform",
        .root = "libs/platform/root.zig",
        .layer = .platform,
        .imports = &.{ "core", "contracts" },
    },
    .{
        .name = "manifest",
        .root = "libs/manifest/root.zig",
        .layer = .service,
        .imports = &.{ "core", "contracts" },
    },
    .{
        .name = "trust",
        .root = "libs/trust/root.zig",
        .layer = .service,
        .imports = &.{ "core", "contracts" },
    },
    .{
        .name = "repository",
        .root = "libs/repository/root.zig",
        .layer = .service,
        .imports = &.{ "core", "contracts" },
    },
    .{
        .name = "package",
        .root = "libs/package/root.zig",
        .layer = .service,
        .imports = &.{ "core", "contracts", "platform", "tar" },
    },
    .{
        .name = "executor",
        .root = "libs/executor/root.zig",
        .layer = .service,
        .imports = &.{ "core", "contracts", "platform" },
    },
    .{
        .name = "resolver",
        .root = "libs/resolver/root.zig",
        .layer = .flow,
        .imports = &.{ "core", "contracts", "manifest", "trust", "repository" },
    },
    .{
        .name = "planner",
        .root = "libs/planner/root.zig",
        .layer = .flow,
        .imports = &.{ "core", "contracts", "manifest", "platform" },
    },
    .{
        .name = "privilege",
        .root = "libs/privilege/root.zig",
        .layer = .flow,
        .imports = &.{ "core", "contracts", "platform", "executor" },
        .macos_frameworks = &.{"Security"},
    },
    .{
        .name = "bootstrap",
        .root = "libs/bootstrap/root.zig",
        .layer = .flow,
        .imports = &.{ "core", "contracts", "platform" },
    },
    .{
        .name = "transaction",
        .root = "libs/transaction/root.zig",
        .layer = .flow,
        .imports = &.{ "core", "contracts", "platform", "executor", "package", "planner" },
    },
    .{
        .name = "portable",
        .root = "libs/portable/root.zig",
        .layer = .flow,
        .imports = &.{
            "core",
            "contracts",
            "platform",
            "manifest",
            "trust",
            "repository",
            "package",
            "resolver",
        },
    },
    .{
        .name = "engine",
        .root = "libs/engine/root.zig",
        .layer = .orchestration,
        .imports = &.{
            "core",
            "contracts",
            "platform",
            "manifest",
            "trust",
            "repository",
            "package",
            "executor",
            "resolver",
            "planner",
            "transaction",
            "privilege",
            "bootstrap",
            "portable",
        },
    },
    .{
        .name = "packager",
        .root = "libs/packager/root.zig",
        .layer = .orchestration,
        .imports = &.{ "core", "contracts", "manifest", "package", "trust", "zstd" },
    },
    .{
        .name = "conformance",
        .root = "libs/conformance/root.zig",
        .layer = .orchestration,
        .imports = &.{ "core", "contracts", "platform" },
    },
    .{ .name = "ui_tokens", .root = "", .layer = .ui_base, .imports = &.{}, .generated = true },
    .{
        .name = "ui_core",
        .root = "libs/ui/core/root.zig",
        .layer = .ui_base,
        .imports = &.{"ui_tokens"},
    },
    .{
        .name = "ui_kit",
        .root = "libs/ui/kit/root.zig",
        .layer = .ui_kit,
        .imports = &.{ "ui_core", "ui_tokens" },
    },
    .{
        .name = "ui_screens",
        .root = "libs/ui/screens/root.zig",
        .layer = .ui_screens,
        .imports = &.{ "ui_core", "ui_kit", "ui_tokens", "contracts", "core" },
    },
    .{
        .name = "ui_render",
        .root = "libs/ui/render/root.zig",
        .layer = .ui_render,
        .imports = &.{ "ui_core", "ui_tokens", "stb_truetype" },
    },
    .{
        .name = "ui_backend",
        .root = "libs/ui/backend/root.zig",
        .layer = .ui_backend,
        .imports = &.{ "ui_core", "ui_kit", "ui_screens", "ui_render", "ui_tokens", "contracts" },
        .macos_frameworks = &.{ "AppKit", "Foundation", "CoreGraphics" },
        .macos_libraries = &.{"objc"},
        .windows_libraries = &.{ "user32", "gdi32", "ole32", "dwmapi", "advapi32" },
    },
    .{
        .name = "stb_truetype",
        .root = "third_party/stb_truetype/bindings.zig",
        .layer = .third_party,
        .imports = &.{},
        .c_library = .stb_truetype,
    },
    .{
        .name = "zstd",
        .root = "third_party/zstd/bindings.zig",
        .layer = .third_party,
        .imports = &.{},
        .c_library = .zstd_compress,
    },
};

/// Modules allowed to spawn processes (enforced by tools/lint, rule spawn-allowlist).
pub const spawn_allowlist = [_][]const u8{
    "libs/component_client/", // Disposable, budgeted instance of a fixed published executable.
    "libs/bootstrap/",
    "libs/portable/",
    "libs/privilege/",
    "libs/platform/",
    "tools/",
    "tests/",
    "apps/",
};

/// Paths allowed to use @ptrCast/@alignCast/@intFromPtr (rule ptr-cast-allowlist).
pub const ptr_cast_allowlist = [_][]const u8{
    "libs/access/posix.zig",
    "libs/access/windows.zig",
    "libs/access/root.zig",
    "libs/component_worker/",
    "libs/evaluator/", // Trusted evaluator/provider callback context, never guest memory.
    "libs/platform/",
    "libs/privilege/",
    "libs/engine/events.zig",
    "libs/ui/backend/",
    "libs/ui/render/",
    "apps/libdistribution/",
    "apps/libcompiler/",
    "apps/runtime/",
    "apps/runtime-v2/",
    "apps/compiler-v2/", // Captured inspector/finalizer callback context, never guest memory.
    "libs/wasm_host/",
    "third_party/",
};

pub fn find(name: []const u8) ?ModuleSpec {
    for (specs) |spec| {
        if (eql(spec.name, name)) return spec;
    }
    return null;
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x != y) return false;
    }
    return true;
}
