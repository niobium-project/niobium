//! Map official Rust and Go archive paths onto one install prefix.

const std = @import("std");

pub const Role = enum { rustc, cargo, std, goroot };

pub const max_components = 64;

pub fn strip(path: []const u8, count: u32) ?[]const u8 {
    var rest = path;
    for (0..count) |_| {
        const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
        rest = rest[slash + 1 ..];
    }
    return if (rest.len == 0) null else rest;
}

pub fn safe(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or std.mem.indexOfScalar(u8, path, '\\') != null) {
        return false;
    }
    if (std.mem.indexOfScalar(u8, path, ':') != null) return false;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, "..") or std.mem.eql(u8, part, ".")) {
            return false;
        }
    }
    return true;
}

/// Destination relative to the tool prefix, or null when the entry is not installed.
pub fn destination(role: Role, path: []const u8) ?[]const u8 {
    switch (role) {
        .rustc => {
            if (std.mem.startsWith(u8, path, "rustc/bin/") or
                std.mem.startsWith(u8, path, "rustc/lib/"))
            {
                return path["rustc/".len..];
            }
            return null;
        },
        .cargo => {
            if (std.mem.startsWith(u8, path, "cargo/bin/")) return path["cargo/".len..];
            return null;
        },
        .std => {
            const marker = "lib/rustlib/";
            const at = std.mem.indexOf(u8, path, marker) orelse return null;
            if (at != 0 and path[at - 1] != '/') return null;
            return path[at..];
        },
        .goroot => return path,
    }
}

/// Official archives keep real binaries under `bin/`, `lib/rustlib/<triple>/bin/`,
/// and Go's `pkg/tool/<host>/`. `bin/` entries are often symlinks to those files.
pub fn executable(path: []const u8) bool {
    if (std.mem.startsWith(u8, path, "bin/")) return true;
    if (std.mem.startsWith(u8, path, "pkg/tool/")) return true;
    return std.mem.indexOf(u8, path, "/bin/") != null;
}

/// `target` is the symlink text. It may use `..` only when the result stays in the prefix.
pub fn linkStaysInside(file_path: []const u8, target: []const u8) bool {
    if (target.len == 0 or target.len > 4096) return false;
    if (target[0] == '/' or std.mem.indexOfScalar(u8, target, '\\') != null) return false;
    if (std.mem.indexOfScalar(u8, target, ':') != null) return false;
    if (std.mem.indexOfScalar(u8, target, 0) != null) return false;
    // SAFETY: pushPath writes `len` entries before any read.
    var parts: [max_components][]const u8 = undefined;
    var len: usize = 0;
    const parent = std.fs.path.dirname(file_path) orelse "";
    if (!pushPath(&parts, &len, parent)) return false;
    return pushPath(&parts, &len, target);
}

fn pushPath(parts: *[max_components][]const u8, len: *usize, path: []const u8) bool {
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (len.* == 0) return false;
            len.* -= 1;
            continue;
        }
        if (len.* == parts.len) return false;
        parts[len.*] = part;
        len.* += 1;
    }
    return true;
}

test "rust and go archive paths land in one prefix" {
    try std.testing.expectEqualStrings(
        "bin/rustc",
        destination(.rustc, "rustc/bin/rustc").?,
    );
    try std.testing.expectEqualStrings(
        "lib/librustc_driver.dylib",
        destination(.rustc, "rustc/lib/librustc_driver.dylib").?,
    );
    try std.testing.expect(destination(.rustc, "install.sh") == null);
    try std.testing.expectEqualStrings("bin/cargo", destination(.cargo, "cargo/bin/cargo").?);
    const std_path = "rust-std-aarch64-apple-darwin/lib/rustlib/" ++
        "wasm32-unknown-unknown/lib/libcore.rlib";
    try std.testing.expect(std.mem.startsWith(u8, destination(.std, std_path).?, "lib/rustlib/"));
    try std.testing.expectEqualStrings("bin/go", destination(.goroot, "bin/go").?);
    try std.testing.expectEqualStrings("bin/go", strip("go/bin/go", 1).?);
}

test "symlink targets stay inside the prefix" {
    try std.testing.expect(linkStaysInside("lib/libstd.dylib", "libstd-hash.dylib"));
    try std.testing.expect(linkStaysInside(
        "bin/rust-lld",
        "../lib/rustlib/aarch64-apple-darwin/bin/gcc-ld/ld",
    ));
    try std.testing.expect(!linkStaysInside("bin/rustc", "../../outside"));
    try std.testing.expect(!linkStaysInside("bin/rustc", "/usr/bin/rustc"));
    try std.testing.expect(!linkStaysInside("bin/rustc", "C:/rustc"));
    try std.testing.expect(!safe("../x"));
    try std.testing.expect(safe("bin/cargo"));
}

test "toolchain binaries outside bin stay executable" {
    try std.testing.expect(executable("bin/rustc"));
    try std.testing.expect(executable("lib/rustlib/aarch64-apple-darwin/bin/rustc"));
    try std.testing.expect(executable("pkg/tool/darwin_arm64/compile"));
    try std.testing.expect(executable("pkg/tool/windows_amd64/asm.exe"));
    try std.testing.expect(!executable("src/runtime/proc.go"));
    try std.testing.expect(!executable("lib/librustc_driver.dylib"));
}
