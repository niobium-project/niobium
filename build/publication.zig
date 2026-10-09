//! Published native bytes use a fixed CPU floor independently of the publisher's CPU.
const std = @import("std");

pub fn baselineTarget(b: *std.Build) std.Build.ResolvedTarget {
    var query = std.Target.Query.fromTarget(&b.graph.host.result);
    query.cpu_model = .baseline;
    query.cpu_features_add = .empty;
    query.cpu_features_sub = .empty;
    const target = b.resolveTargetQuery(query);
    var baseline = std.Target.Cpu.baseline(target.result.cpu.arch, target.result.os);
    baseline.features.populateDependencies(target.result.cpu.arch.allFeaturesList());
    std.debug.assert(target.result.cpu.model == baseline.model);
    std.debug.assert(target.result.cpu.features.eql(baseline.features));
    return target;
}

pub fn nativeProfile(target: std.Target) error{UnqualifiedNativeProfile}![]const u8 {
    return switch (target.os.tag) {
        .macos => if (target.cpu.arch == .aarch64 and target.abi == .none)
            "aarch64-macos-baseline-v1"
        else
            error.UnqualifiedNativeProfile,
        .linux => if (target.cpu.arch != .x86_64)
            error.UnqualifiedNativeProfile
        else switch (target.abi) {
            .musl => "x86_64-linux-musl-baseline-v1",
            .gnu => "x86_64-linux-gnu-baseline-v1",
            else => error.UnqualifiedNativeProfile,
        },
        .windows => if (target.cpu.arch == .x86_64 and target.abi == .gnu)
            "x86_64-windows-gnu-baseline-v1"
        else
            error.UnqualifiedNativeProfile,
        else => error.UnqualifiedNativeProfile,
    };
}
