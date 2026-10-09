//! macOS host integrations (docs/spec/platform-contract.md#macos):
//! - shortcut: symlink `~/Applications/<id>` (user) or `/Applications/<id>` (machine) pointing
//!   at `<root>/current/<target>`, so it follows every update without being rewritten;
//! - service: launchd plist in `~/Library/LaunchAgents` or `/Library/LaunchDaemons`, then
//!   file lifecycle only; launchd activation is not implemented;
//! - file association and registration: CapabilityUnsupported (declared by the app bundle;
//!   installation.json is the registration).

const std = @import("std");
const contracts = @import("contracts");
const api = @import("api.zig");
const files = @import("files.zig");
const host = @import("host.zig");
const names = @import("names.zig");

const Error = api.Error;

/// Shortcut links the framework made resolve through the managed `current` pointer.
const link_owner = "/current/";
const Allocator = std.mem.Allocator;

fn spec(
    h: *const host.Host,
    arena: Allocator,
    request: *const api.IntegrationRequest,
) Error!files.Spec {
    const i = request.integration;
    const exe = try host.executable(arena, '/', request.root, i.target);
    switch (i.kind) {
        .shortcut => return .{
            .final = try h.scoped(
                arena,
                request.scope,
                &.{ "Applications", try names.segment(i.id) },
            ),
            .body = .{ .link = exe },
            .owner = link_owner,
        },
        .service => {
            const label = try serviceLabel(arena, request.product_id, i.id);
            const file = try std.fmt.allocPrint(arena, "{s}.plist", .{label});
            const final = switch (request.scope) {
                .user => try h.userPath(arena, &.{ "Library", "LaunchAgents", file }),
                .machine => try h.systemPath(arena, &.{ "Library", "LaunchDaemons", file }),
            };
            return .{
                .final = final,
                .body = .{ .content = try plist(arena, label, exe, i.start == .auto) },
            };
        },
        .file_association, .registration => return error.CapabilityUnsupported,
    }
}

pub fn machineDirs(h: *const host.Host, arena: Allocator) Error![]const []const u8 {
    return arena.dupe([]const u8, &.{
        try h.systemPath(arena, &.{"Applications"}),
        try h.systemPath(arena, &.{ "Library", "LaunchDaemons" }),
    });
}

fn serviceLabel(arena: Allocator, product_id: []const u8, id: []const u8) Error![]const u8 {
    const label = try std.fmt.allocPrint(arena, "{s}.{s}", .{ product_id, id });
    return names.token(label);
}

/// launchd job definition; the marker comment identifies files the framework owns.
pub fn plist(
    arena: Allocator,
    label: []const u8,
    exe: []const u8,
    run_at_load: bool,
) Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;
    w.print(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
        \\  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<!-- {s} -->
        \\<plist version="1.0">
        \\<dict>
        \\  <key>Label</key>
        \\  <string>{s}</string>
        \\  <key>ProgramArguments</key>
        \\  <array>
        \\    <string>
    , .{ files.marker, label }) catch return error.OutOfMemory;
    try files.xmlText(w, exe);
    w.print(
        \\</string>
        \\  </array>
        \\  <key>RunAtLoad</key>
        \\  <{s}/>
        \\</dict>
        \\</plist>
        \\
    , .{if (run_at_load) "true" else "false"}) catch return error.OutOfMemory;
    return out.written();
}

pub fn prepare(
    h: *const host.Host,
    arena: Allocator,
    request: *const api.IntegrationRequest,
) Error!void {
    return files.prepare(h.local, try spec(h, arena, request), request.tx);
}

pub fn discard(
    h: *const host.Host,
    arena: Allocator,
    request: *const api.IntegrationRequest,
) Error!void {
    return files.discard(h.local, (try spec(h, arena, request)).final, request.tx);
}

pub fn activate(
    h: *const host.Host,
    arena: Allocator,
    request: *const api.IntegrationRequest,
) Error![]const u8 {
    const s = try spec(h, arena, request);
    try files.activate(h.local, s, request.tx);
    return arena.dupe(u8, s.final);
}

pub fn remove(
    h: *const host.Host,
    arena: Allocator,
    installed: contracts.installation.Integration,
) Error!void {
    _ = arena;
    switch (installed.kind) {
        .shortcut, .service => {},
        .file_association, .registration => return error.CapabilityUnsupported,
    }
    const owner = if (installed.kind == .shortcut) link_owner else files.marker;
    return files.remove(h.local, installed.location, owner);
}

test "launchd plist escapes and marks ownership" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const text = try plist(arena.allocator(), "com.example.hello.agent", "/A&B/current/x", true);
    try std.testing.expect(std.mem.find(u8, text, "<string>/A&amp;B/current/x</string>") != null);
    try std.testing.expect(std.mem.find(u8, text, files.marker) != null);
    try std.testing.expect(std.mem.find(u8, text, "<true/>") != null);
    try std.testing.expectError(
        error.PlatformIntegrationFailed,
        plist(arena.allocator(), "l", "/a\nb", false),
    );
}
