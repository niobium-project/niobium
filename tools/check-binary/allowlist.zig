//! Declared dynamic dependencies per target and artifact kind. Anything else is a gate failure
//! ("undeclared dynamic dependency = 0"). Windows names compare case-insensitively.

pub const Kind = enum { exe, dylib };
pub const Profile = enum { component };

pub const Rule = struct {
    target: []const u8,
    kind: Kind,
    dependencies: []const []const u8,
    format: @import("bytes.zig").Format,
    interpreter: ?[]const u8 = null,
};

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
