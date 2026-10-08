//! Model checks are independent of author language and contain no product distribution policy.

const std = @import("std");
const contracts = @import("contracts");
const root = @import("root.zig");
const Error = root.Error;

pub fn program(value: root.Program, limits: contracts.Limits) Error!void {
    if (value.schema != 1 or value.runtime_abi != 1) return error.ProgramUnsupported;
    try identifier(value.product_id);
    if (value.release_sequence == 0 or value.model_version == 0) return error.ProgramInvalid;
    try entries(root.Input, value.inputs, limits);
    try entries(root.Library, value.libraries, limits);
    try entries(root.Asset, value.assets, limits);
    try entries(root.Resource, value.resources, limits);
    try entries(root.Instance, value.instances, limits);
    try migrations(value.upgrades, value.model_version, limits);
    for (value.inputs) |input| {
        if (input.default.len > limits.program_state_bytes) return error.ProgramLimit;
    }
    for (value.libraries) |library| {
        if (library.abi != 1) return error.ProgramUnsupported;
        try blob(library.wasm_hex, library.sha256, limits.wasm_module_bytes);
    }
    for (value.assets) |asset| try blob(asset.data_hex, asset.sha256, limits.program_blob_bytes);
    for (value.resources, 0..) |resource, index| {
        try resourcePath(resource.path);
        for (value.resources[0..index]) |previous| {
            if (pathsConflict(previous.path, resource.path)) {
                return error.ProgramDuplicate;
            }
        }
    }
    for (value.instances, 0..) |instance, index| {
        try instanceRules(value, instance, limits);
        for (value.instances[0..index]) |previous| {
            for (instance.resources) |resource| {
                for (previous.resources) |owned| {
                    if (std.mem.eql(u8, resource, owned)) return error.ProgramDuplicate;
                }
            }
        }
    }
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

fn instanceRules(
    value: root.Program,
    instance: root.Instance,
    limits: contracts.Limits,
) Error!void {
    if (root.find(root.Library, value.libraries, instance.library) == null) {
        return error.ProgramReference;
    }
    if (instance.state_version == 0) return error.ProgramInvalid;
    try references(root.Input, value.inputs, instance.inputs, limits);
    try references(root.Asset, value.assets, instance.assets, limits);
    try references(root.Resource, value.resources, instance.resources, limits);
    try migrations(instance.migrations, instance.state_version, limits);
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

fn entries(comptime T: type, items: []const T, limits: contracts.Limits) Error!void {
    if (items.len > limits.program_items) return error.ProgramLimit;
    for (items, 0..) |item, index| {
        try identifier(item.id);
        for (items[0..index]) |previous| {
            if (std.mem.eql(u8, item.id, previous.id)) return error.ProgramDuplicate;
        }
    }
}

fn references(
    comptime T: type,
    items: []const T,
    refs: []const []const u8,
    limits: contracts.Limits,
) Error!void {
    if (refs.len > limits.program_items) return error.ProgramLimit;
    for (refs, 0..) |ref, index| {
        if (root.find(T, items, ref) == null) return error.ProgramReference;
        for (refs[0..index]) |previous| {
            if (std.mem.eql(u8, previous, ref)) return error.ProgramDuplicate;
        }
    }
}

fn migrations(items: []const root.Migration, target: u32, limits: contracts.Limits) Error!void {
    try entries(root.Migration, items, limits);
    for (items, 0..) |item, index| {
        if (item.from == 0 or item.from >= item.to or item.to != target) {
            return error.ProgramInvalid;
        }
        for (items[0..index]) |previous| {
            if (previous.from == item.from) return error.ProgramDuplicate;
        }
    }
}

fn blob(text: []const u8, expected: []const u8, max_bytes: u32) Error!void {
    if (text.len % 2 != 0 or text.len / 2 > max_bytes) return error.ProgramLimit;
    if (expected.len != 64) return error.ProgramDigest;
    var hasher: std.crypto.hash.sha2.Sha256 = .init(.{});
    var index: usize = 0;
    while (index < text.len) : (index += 2) {
        const byte = (try root.nibble(text[index])) * 16 + try root.nibble(text[index + 1]);
        hasher.update(&.{byte});
    }
    const actual = std.fmt.bytesToHex(hasher.finalResult(), .lower);
    if (!std.mem.eql(u8, &actual, expected)) return error.ProgramDigest;
}
