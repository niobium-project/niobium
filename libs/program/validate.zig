//! Model checks are independent of author language and contain no product distribution policy.

const std = @import("std");
const contracts = @import("contracts");
const root = @import("root.zig");
const Error = root.Error;

pub fn inputValue(bytes: []const u8, limits: contracts.Limits) Error!void {
    if (bytes.len > limits.program_state_bytes) return error.ProgramLimit;
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.ProgramInvalid;
}

fn ancestor(parent: []const u8, child: []const u8) bool {
    if (parent.len >= child.len) return false;
    return child[parent.len] == '/' and std.ascii.eqlIgnoreCase(parent, child[0..parent.len]);
}

pub fn pathsConflict(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b) or ancestor(a, b) or ancestor(b, a);
}

/// The macOS PoC uses printable ASCII resource names to avoid filesystem Unicode aliases.
/// Installation-root names are not restricted by this resource profile.
pub fn resourcePath(text: []const u8) Error!void {
    try path(text);
    if (pathsConflict(text, ".niobium-generation")) return error.ProgramPath;
    var depth: u16 = 1;
    for (text) |byte| {
        if (byte < 32 or byte > 126) return error.ProgramPath;
        if (byte == '/') depth += 1;
    }
    if (depth > (contracts.Limits{}).path_components - 2) return error.ProgramPath;
}

pub fn identifier(text: []const u8) Error!void {
    if (text.len == 0 or text.len > 128) return error.ProgramInvalid;
    for (text) |byte| {
        if (std.ascii.isLower(byte) or std.ascii.isDigit(byte)) continue;
        if (byte == '.' or byte == '_' or byte == '-') continue;
        return error.ProgramInvalid;
    }
}

pub fn path(text: []const u8) Error!void {
    if (text.len == 0 or text.len > (contracts.Limits{}).path_bytes) return error.ProgramPath;
    if (!std.unicode.utf8ValidateSlice(text)) return error.ProgramPath;
    if (text[0] == '/' or std.mem.indexOfScalar(u8, text, '\\') != null) return error.ProgramPath;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.ProgramPath;
    var parts = std.mem.splitScalar(u8, text, '/');
    var count: u16 = 0;
    while (parts.next()) |part| {
        count += 1;
        if (count > (contracts.Limits{}).path_components) return error.ProgramPath;
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) {
            return error.ProgramPath;
        }
    }
}
