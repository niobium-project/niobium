//! Public `zig build` step names. Top-level names are a closed set; every other
//! name is `namespace:leaf` or `namespace:leaf:detail`.

const std = @import("std");

pub const top_level = [_][]const u8{ "fmt", "lint", "check", "test", "verify", "run" };

pub const names = [_][]const u8{
    "fmt",
    "fmt:fix",
    "lint",
    "lint:baseline",
    "check",
    "check:docs",
    "check:commits",
    "check:binary",
    "check:size",
    "check:cross",
    "test",
    "test:cross",
    "test:sim",
    "test:fuzz",
    "test:tsan",
    "test:e2e",
    "test:c-smoke",
    "test:golden",
    "test:evidence",
    "test:kernel",
    "test:kernel-wire",
    "test:image",
    "test:access",
    "test:core",
    "test:component",
    "test:author",
    "test:compiler",
    "verify",
    "run",
    "compiler:build",
    "compiler:linux-x64",
    "runtime:build",
    "runtime:linux-x64",
    "runtime:windows-x64",
    "core:sdk",
    "core:e2e",
    "core:cross-tools",
    "aot:build",
    "aot:test",
    "aot:e2e",
    "aot:size",
    "aot:authoring",
    "ui:gallery",
    "ui:workbench",
    "vm:smoke",
    "tools:install",
    "tools:doctor",
    "hooks:install",
    "hooks:pre-commit",
    "hooks:pre-push",
    "example:hello",
    "example:tutorial",
    "example:tutorial:tools",
};

pub fn step(b: *std.Build, name: []const u8, description: []const u8) *std.Build.Step {
    std.debug.assert(listed(name));
    return b.step(name, description);
}

pub fn listed(name: []const u8) bool {
    for (names) |known| {
        if (std.mem.eql(u8, known, name)) return true;
    }
    return false;
}

pub fn valid(name: []const u8) bool {
    var colons: u8 = 0;
    var part_len: usize = 0;
    if (name.len == 0 or name[0] == ':') return false;
    for (name) |byte| {
        if (byte == ':') {
            if (part_len == 0) return false;
            colons += 1;
            if (colons > 2) return false;
            part_len = 0;
            continue;
        }
        const ok = std.ascii.isAlphanumeric(byte) or byte == '-';
        if (!ok) return false;
        if (part_len == 0 and !std.ascii.isLower(byte)) return false;
        part_len += 1;
    }
    if (part_len == 0) return false;
    if (colons == 0) return topLevel(name);
    return true;
}

fn topLevel(name: []const u8) bool {
    for (top_level) |known| {
        if (std.mem.eql(u8, known, name)) return true;
    }
    return false;
}

test "public steps are listed once and use the closed naming rule" {
    for (names, 0..) |name, index| {
        try std.testing.expect(valid(name));
        try std.testing.expect(listed(name));
        for (names[index + 1 ..]) |later| {
            try std.testing.expect(!std.mem.eql(u8, name, later));
        }
    }
    for (top_level) |name| try std.testing.expect(listed(name));
    try std.testing.expect(!valid("fmt-fix"));
    try std.testing.expect(!valid("Example"));
    try std.testing.expect(!valid("a:b:c:d"));
    try std.testing.expect(!valid("custom"));
}
