//! The existing checked fetcher resolves a separate, pinned build-tool manifest.
const std = @import("std");

pub const Tools = struct {
    wasm_tools: std.Build.LazyPath,
    wit_bindgen: std.Build.LazyPath,
    wasi_sysroot: std.Build.LazyPath,
};

pub fn supported(host: std.Target) bool {
    return switch (host.os.tag) {
        .macos => host.cpu.arch == .aarch64,
        .linux, .windows => host.cpu.arch == .x86_64,
        else => false,
    };
}

pub fn add(b: *std.Build, fetcher: *std.Build.Step.Compile) Tools {
    std.debug.assert(supported(b.graph.host.result));
    // SAFETY: The comptime field loop initializes every Tools field.
    var tools: Tools = undefined;
    inline for (comptime std.meta.fieldNames(Tools)) |name| {
        const is_sysroot = comptime std.mem.eql(u8, name, "wasi_sysroot");
        const package = if (is_sysroot) name else switch (b.graph.host.result.os.tag) {
            .macos => name,
            .linux => b.fmt("{s}_linux_x64", .{name}),
            .windows => b.fmt("{s}_windows_x64", .{name}),
            else => @panic("unsupported component tool host"),
        };
        const run = b.addRunArtifact(fetcher);
        run.setName(b.fmt("fetch component {s}", .{name}));
        run.addArg("--manifest");
        run.addFileArg(b.path("third_party/wasmtime/toolchain.zon"));
        run.addArgs(&.{ "--package", package, "--out" });
        @field(tools, name) = run.addOutputDirectoryArg(name);
    }
    return tools;
}

pub fn executable(
    b: *std.Build,
    directory: std.Build.LazyPath,
    name: []const u8,
) std.Build.LazyPath {
    const suffix = if (b.graph.host.result.os.tag == .windows) ".exe" else "";
    return directory.path(b, b.fmt("{s}{s}", .{ name, suffix }));
}
