//! A host-only process envelope. WIT values cross the guest boundary through the standard C API.
const value = @import("value.zig");
const wit = @import("wit.zig");

pub const FileSource = struct { path: []const u8, length: u32, sha256: []const u8 };
pub const RangeSource = struct { path: []const u8, offset: u64, length: u32, sha256: []const u8 };
pub const Source = union(enum) { file: FileSource, range: RangeSource };
pub const Request = struct {
    schema: u32 = 1,
    action: enum { inspect, invoke },
    source: Source,
    interface: []const u8 = "",
    function: []const u8 = "",
    args: []const value.Value = &.{},
    allowed_imports: []const []const u8 = &.{},
};
pub const Diagnostic = struct { code: []const u8, message: []const u8 };
pub const Response = struct {
    schema: u32 = 1,
    status: enum { ok, @"error" },
    result: ?value.Value = null,
    inspection: ?wit.Inspection = null,
    @"error": ?Diagnostic = null,
};
