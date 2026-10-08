//! Host-side signing tools use the same pinned fetch boundary as other compiler tools.
const std = @import("std");
pub const Tool = struct { executable: std.Build.LazyPath, notice: std.Build.LazyPath };
pub fn add(b: *std.Build, fetcher: *std.Build.Step.Compile) Tool {
    const host = b.graph.host.result;
    const package = switch (host.os.tag) {
        .macos => "macos_arm64",
        .linux => "linux_x64",
        .windows => "windows_x64",
        else => unreachable, // Caller requires a qualified host tool profile.
    };
    const fetch = b.addRunArtifact(fetcher);
    fetch.addArg("--manifest");
    fetch.addFileArg(b.path("third_party/apple_codesign/toolchain.zon"));
    fetch.addArgs(&.{ "--package", package, "--out" });
    const directory = fetch.addOutputDirectoryArg("signer");
    const name = if (host.os.tag == .windows) "rcodesign.exe" else "rcodesign";
    return .{
        .executable = directory.path(b, name),
        .notice = directory.path(b, "COPYING"),
    };
}
