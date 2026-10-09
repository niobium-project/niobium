//! Declared dynamic dependencies per target and artifact kind. Anything else is a gate failure
//! ("undeclared dynamic dependency = 0"). Windows names compare case-insensitively.

pub const Kind = enum { exe, dylib };
pub const Profile = enum { legacy, component };

pub const Rule = struct {
    target: []const u8,
    kind: Kind,
    dependencies: []const []const u8,
    format: ?@import("bytes.zig").Format = null,
    interpreter: ?[]const u8 = null,
};

const windows_system = [_][]const u8{
    "kernel32.dll",         "ntdll.dll", "advapi32.dll", "ws2_32.dll", "crypt32.dll", "bcrypt.dll",
    "bcryptprimitives.dll",
};

const windows_dylib = windows_system ++ [_][]const u8{"shell32.dll"};

const windows_gui = windows_system ++ [_][]const u8{
    "user32.dll", "gdi32.dll",  "shell32.dll", "ole32.dll", "comdlg32.dll", "uxtheme.dll",
    "dwmapi.dll", "shcore.dll",
};

const frameworks = "/System/Library/Frameworks/";

const macos_system = [_][]const u8{
    "/usr/lib/libSystem.B.dylib",
    frameworks ++ "CoreFoundation.framework/Versions/A/CoreFoundation",
    frameworks ++ "Security.framework/Versions/A/Security",
};

const macos_gui = macos_system ++ [_][]const u8{
    "/usr/lib/libobjc.A.dylib",
    frameworks ++ "AppKit.framework/Versions/C/AppKit",
    frameworks ++ "Foundation.framework/Versions/C/Foundation",
    frameworks ++ "CoreGraphics.framework/Versions/A/CoreGraphics",
};

pub const rules = [_]Rule{
    .{ .target = "x86_64-windows", .kind = .exe, .dependencies = &windows_gui },
    // shell32: `runas` elevation of the privilege helper (ShellExecuteExW).
    .{ .target = "x86_64-windows", .kind = .dylib, .dependencies = &windows_dylib },
    .{ .target = "aarch64-macos", .kind = .exe, .dependencies = &macos_gui },
    .{ .target = "aarch64-macos", .kind = .dylib, .dependencies = &macos_system },
    // Linux artifacts are static musl; X11 is spoken over the socket, not via libX11.
    .{ .target = "x86_64-linux", .kind = .exe, .dependencies = &.{} },
    .{ .target = "x86_64-linux", .kind = .dylib, .dependencies = &.{} },
    .{ .target = "aarch64-linux", .kind = .exe, .dependencies = &.{} },
    .{ .target = "aarch64-linux", .kind = .dylib, .dependencies = &.{} },
};

/// ABI-qualified publication rules are independent of retained artifact policy.
const component_windows = [_][]const u8{
    "bcryptprimitives.dll",
    "kernel32.dll",
    "ntdll.dll",
    "advapi32.dll",
    "api-ms-win-crt-heap-l1-1-0.dll",
    "api-ms-win-crt-locale-l1-1-0.dll",
    "api-ms-win-crt-runtime-l1-1-0.dll",
    "api-ms-win-crt-stdio-l1-1-0.dll",
    "api-ms-win-crt-environment-l1-1-0.dll",
    "api-ms-win-crt-math-l1-1-0.dll",
    "api-ms-win-core-synch-l1-2-0.dll",
};

pub const component_rules = [_]Rule{
    .{
        .target = "aarch64-macos",
        .kind = .exe,
        .format = .macho,
        .dependencies = &.{"/usr/lib/libSystem.B.dylib"},
    },
    .{
        .target = "x86_64-windows-gnu",
        .kind = .exe,
        .format = .pe,
        .dependencies = &component_windows,
    },
    .{ .target = "x86_64-linux-musl", .kind = .exe, .format = .elf, .dependencies = &.{} },
    .{
        .target = "x86_64-linux-gnu",
        .kind = .exe,
        .format = .elf,
        .dependencies = &.{ "libc.so.6", "ld-linux-x86-64.so.2" },
        .interpreter = "/lib64/ld-linux-x86-64.so.2",
    },
};
