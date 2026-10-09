//! Independent TUF state, platform receipts and UI presentation data.

const std = @import("std");
const json = @import("json.zig");
const ids = @import("ids.zig");

pub const schema_version = 1;
pub const max_state_bytes = 2 << 20;

pub const IntegrationKind = enum { shortcut, file_association, service, registration };

pub const Integration = struct {
    kind: IntegrationKind,
    id: []const u8,
    /// Platform location (link path, registry key, unit file) written at install time.
    location: []const u8,
};

pub const TrustState = struct {
    schema: u32 = schema_version,
    root_version: u64,
    timestamp_version: u64,
    snapshot_version: u64,
    targets_version: u64,
    channel_version: u64,
    release_sequence: u64,
};

pub const Mode = enum { generic, branded };

/// What the GUI shows for a branded product. Text is plain UTF-8, never markup; absent fields
/// fall back to the generic copy.
pub const Branding = struct {
    product_name: ?[]const u8 = null,
    publisher: ?[]const u8 = null,
    /// `#RRGGBB`; rejected at startup when no shade of it reaches the contrast rules.
    accent: ?[]const u8 = null,
    welcome_title: ?[]const u8 = null,
    welcome_body: ?[]const u8 = null,
    complete_body: ?[]const u8 = null,
    /// License text shown before install; installing implies accepting it.
    license: ?[]const u8 = null,
    /// Base64 of a PNG logo, at most `max_logo_bytes` decoded.
    logo_png: ?[]const u8 = null,
};

pub const max_logo_bytes = 256 * 1024;
pub const max_license_bytes = 64 * 1024;

/// UI presentation configuration; runtime product identity belongs to `program.model`.
pub const ProductConfig = struct {
    schema: u32,
    mode: Mode,
    branding: Branding = .{},
};

pub fn decodeTrustState(arena: std.mem.Allocator, bytes: []const u8) json.DecodeError!TrustState {
    return json.decode(
        TrustState,
        arena,
        bytes,
        .{ .max_bytes = 64 << 10, .max_schema = schema_version },
    );
}

pub fn decodeProductConfig(
    arena: std.mem.Allocator,
    bytes: []const u8,
) json.DecodeError!ProductConfig {
    return json.decode(
        ProductConfig,
        arena,
        bytes,
        .{ .max_bytes = 1 << 20, .max_schema = schema_version },
    );
}

pub fn encode(arena: std.mem.Allocator, value: anytype) error{OutOfMemory}![]u8 {
    return std.json.Stringify.valueAlloc(arena, value, .{ .whitespace = .indent_2 });
}
