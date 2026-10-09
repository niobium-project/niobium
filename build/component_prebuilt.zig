//! Cached engine archive and wasm32 guests for the pull-request compile.
//! Absent options keep the cargo graph. The export step copies Linux cargo
//! outputs into ci-prebuilt so main can fill that cache after a source build.
const std = @import("std");
const commands = @import("commands.zig");

pub const export_dir = "ci-prebuilt";
pub const engine_archive = "libniobium_wasmtime.a";

pub const Guest = enum {
    files,
    reference,
    reference_revision_two,
    qualification,

    pub fn fileName(guest: Guest) []const u8 {
        return switch (guest) {
            .files => "niobium_stdlib_files.wasm",
            .reference => "niobium_reference_library.wasm",
            .reference_revision_two => "niobium_reference_library-revision-two.wasm",
            .qualification => "niobium_component_consumer.wasm",
        };
    }
};

pub const Cache = struct {
    engine: ?std.Build.LazyPath,
    guests: ?std.Build.LazyPath,
    mismatch: ?*std.Build.Step,
};

pub const Export = struct {
    step: *std.Build.Step,
    prepare: *std.Build.Step,
};

pub fn fromBuild(b: *std.Build) Cache {
    const engine = b.option(
        std.Build.LazyPath,
        "prebuilt-engine",
        "Host libniobium_wasmtime archive; skips the engine cargo build",
    );
    const guests = b.option(
        std.Build.LazyPath,
        "prebuilt-guests",
        "Directory of wasm32 cargo outputs; skips guest cargo builds",
    );
    if ((engine == null) != (guests == null)) {
        return .{
            .engine = null,
            .guests = null,
            .mismatch = &b.addFail(
                "prebuilt-engine and prebuilt-guests must be set together",
            ).step,
        };
    }
    return .{ .engine = engine, .guests = guests, .mismatch = null };
}

pub fn createExport(b: *std.Build) Export {
    const step = commands.step(
        b,
        "core:prebuilt-export",
        "Copy the Linux engine archive and wasm32 guests into ci-prebuilt",
    );
    if (b.graph.host.result.os.tag != .linux or b.graph.host.result.cpu.arch != .x86_64) {
        step.dependOn(&b.addFail("prebuilt-export runs on the Linux x64 publisher").step);
    }
    const mkdir = b.addSystemCommand(&.{ "mkdir", "-p", export_dir });
    mkdir.setCwd(b.path("."));
    mkdir.has_side_effects = true;
    return .{ .step = step, .prepare = &mkdir.step };
}

pub fn exportFile(
    b: *std.Build,
    exported: Export,
    source: std.Build.LazyPath,
    name: []const u8,
) void {
    std.debug.assert(name.len > 0);
    std.debug.assert(std.mem.indexOfScalar(u8, name, '/') == null);
    const run = b.addSystemCommand(&.{ "cp", "--" });
    run.setCwd(b.path("."));
    run.has_side_effects = true;
    run.addFileArg(source);
    run.addArg(b.fmt("{s}/{s}", .{ export_dir, name }));
    run.step.dependOn(exported.prepare);
    exported.step.dependOn(&run.step);
}

pub fn guestSource(
    cache: Cache,
    b: *std.Build,
    guest: Guest,
    compiled: std.Build.LazyPath,
) std.Build.LazyPath {
    const root = cache.guests orelse return compiled;
    return root.path(b, guest.fileName());
}

pub fn engineLog(b: *std.Build) std.Build.LazyPath {
    return b.addWriteFiles().add(
        "engine-build.log",
        "prebuilt engine archive; cargo was not run\n",
    );
}

test "guest cache names are distinct wasm files" {
    const names = [_][]const u8{
        Guest.files.fileName(),
        Guest.reference.fileName(),
        Guest.reference_revision_two.fileName(),
        Guest.qualification.fileName(),
    };
    for (names, 0..) |name, index| {
        try std.testing.expect(std.mem.endsWith(u8, name, ".wasm"));
        try std.testing.expect(std.mem.indexOfScalar(u8, name, '/') == null);
        for (names[index + 1 ..]) |later| {
            try std.testing.expect(!std.mem.eql(u8, name, later));
        }
    }
}
