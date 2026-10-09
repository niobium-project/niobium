//! File-backed platform integration requests shared with the privilege IPC profile.

const installation = @import("installation.zig");

pub const ServiceStart = enum { auto, manual };

pub const Integration = struct {
    kind: installation.IntegrationKind,
    /// Stable id (shortcut name, extension, service id).
    id: []const u8,
    /// Display name or description.
    label: []const u8,
    /// Executable path relative to `current/` (`<component>/<entrypoint path>`); for
    /// `registration` it is the maintainer executable relative to the install root.
    /// Uses forward slashes on every OS; the platform backend renders native separators.
    target: []const u8,
    start: ?ServiceStart = null,
    /// Machine scope integrations go through the privilege helper.
    privileged: bool = false,
};
