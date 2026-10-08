//! Bounded durable wire contracts. Validation always precedes recovery mutations.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const content = @import("content");
const access = @import("access");
const t = @import("types.zig");
const Error = t.Error;
const limits = contracts.limits.default;
const json_options: contracts.json.Options = .{
    .max_schema = 2,
    .max_bytes = limits.runtime_plan_bytes,
    .limits = .{
        .json_depth = program.model.wire_depth,
        .json_string_bytes = limits.access_acl_bytes * 2,
    },
};

pub fn encode(arena: std.mem.Allocator, value: anytype) Error![]const u8 {
    var scratch: [4096]u8 = undefined; // SAFETY: the writer initializes buffered bytes.
    var counter: std.Io.Writer.Discarding = .init(&scratch);
    std.json.Stringify.value(value, .{}, &counter.writer) catch return error.KernelLimit;
    if (counter.fullCount() > limits.runtime_plan_bytes) return error.KernelLimit;
    const size = std.math.cast(usize, counter.fullCount()) orelse return error.KernelLimit;
    const buffer = try arena.alloc(u8, size);
    var writer: std.Io.Writer = .fixed(buffer);
    std.json.Stringify.value(value, .{}, &writer) catch return error.KernelLimit;
    const bytes = buffer[0..writer.end];
    try contracts.json.validate(arena, bytes, json_options);
    return bytes;
}

pub fn decode(comptime T: type, arena: std.mem.Allocator, bytes: []const u8) Error!T {
    return contracts.json.decode(T, arena, bytes, json_options);
}

pub fn nonce(text: []const u8) Error!void {
    if (text.len != 32) return error.KernelState;
    for (text) |byte| {
        if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f')) {
            return error.KernelState;
        }
    }
}

pub fn hash(text: []const u8) Error!void {
    if (contracts.ids.parseHex32(text) == null) return error.KernelState;
}

pub fn path(text: []const u8) Error!void {
    try content.names.check(text, .{});
    if (@import("builtin").os.tag != .windows) return;
    var parts = std.mem.splitScalar(u8, text, '/');
    while (parts.next()) |part| {
        if (part[part.len - 1] == '.' or part[part.len - 1] == ' ') return error.ProgramPath;
        for (part) |byte| {
            if (byte < 32 or std.mem.findScalar(u8, ":*?\"<>|\\", byte) != null) {
                return error.ProgramPath;
            }
        }
        const stem = part[0 .. std.mem.findScalar(u8, part, '.') orelse part.len];
        for ([_][]const u8{ "con", "prn", "aux", "nul" }) |reserved| {
            if (std.ascii.eqlIgnoreCase(stem, reserved)) return error.ProgramPath;
        }
        if (stem.len == 4 and stem[3] >= '1' and stem[3] <= '9' and
            (std.ascii.eqlIgnoreCase(stem[0..3], "com") or
                std.ascii.eqlIgnoreCase(stem[0..3], "lpt"))) return error.ProgramPath;
    }
}

pub fn linkTarget(text: []const u8) Error!void {
    if (text.len == 0 or text.len > limits.path_bytes or text[0] == '/' or
        !std.unicode.utf8ValidateSlice(text) or std.mem.findScalar(u8, text, 0) != null)
    {
        return error.ContentInvalid;
    }
    if (@import("builtin").os.tag != .windows) return;
    var parts = std.mem.splitScalar(u8, text, '/');
    var count: u32 = 0;
    while (parts.next()) |part| {
        count += 1;
        if (count > limits.path_components) return error.KernelLimit;
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) continue;
        try path(part);
    }
}

/// Logical content identity keeps exact bytes; Windows lookup uses native separators.
pub fn nativeLinkTarget(arena: std.mem.Allocator, logical: []const u8) Error![]const u8 {
    try linkTarget(logical);
    if (@import("builtin").os.tag != .windows) return logical;
    const native = try arena.dupe(u8, logical);
    std.mem.replaceScalar(u8, native, '/', '\\');
    return native;
}

pub fn bindings(roots: []const t.RootBinding, coordinator: []const u8) Error!void {
    if (roots.len == 0 or roots.len > limits.program_items) return error.KernelLimit;
    if (program.find(t.RootBinding, roots, coordinator) == null) return error.KernelInvalid;
    for (roots, 0..) |root, index| {
        try program.validation.identifier(root.id);
        if (!std.fs.path.isAbsolute(root.path) or root.path.len > limits.path_bytes or
            !std.unicode.utf8ValidateSlice(root.path) or
            std.mem.findScalar(u8, root.path, 0) != null) return error.KernelInvalid;
        for (roots[0..index]) |other| {
            if (std.mem.eql(u8, root.id, other.id) or
                std.mem.eql(u8, root.path, other.path)) return error.KernelConflict;
            if (pathWithin(root.path, other.path) or pathWithin(other.path, root.path)) {
                return error.KernelConflict;
            }
        }
    }
}

fn pathWithin(parent: []const u8, child: []const u8) bool {
    return child.len > parent.len and std.mem.eql(u8, parent, child[0..parent.len]) and
        (child[parent.len] == '/' or
            (@import("builtin").os.tag == .windows and child[parent.len] == '\\'));
}

pub fn owner(value: t.Owner, expected: t.Owner) Error!void {
    if (value.schema != 2) return error.KernelUnsupported;
    try nonce(value.instance);
    try program.validation.identifier(value.product_id);
    try bindings(value.roots, value.state_root);
    if (!std.mem.eql(u8, value.instance, expected.instance) or
        !std.mem.eql(u8, value.product_id, expected.product_id) or
        !std.mem.eql(u8, value.root, expected.root) or
        !std.mem.eql(u8, value.state_root, expected.state_root) or
        !sameBindings(value.roots, expected.roots)) return error.KernelOwnership;
}

pub fn sameBindings(left: []const t.RootBinding, right: []const t.RootBinding) bool {
    if (left.len != right.len) return false;
    for (left) |item| {
        const found = program.find(t.RootBinding, right, item.id) orelse return false;
        if (!std.mem.eql(u8, item.path, found.path)) return false;
    }
    return true;
}

pub fn snapshot(arena: std.mem.Allocator, value: t.Snapshot, ownership: t.Owner) Error!void {
    if (value.schema != 2) return error.KernelUnsupported;
    if (!std.mem.eql(u8, value.instance, ownership.instance) or
        !std.mem.eql(u8, value.product_id, ownership.product_id)) return error.KernelOwnership;
    if (value.release_sequence == 0 or value.model_version == 0) return error.KernelState;
    try hash(value.program_sha256);
    if (value.inputs.len > limits.program_items or value.calls.len > limits.program_items or
        value.migrations.len > limits.plan_ops or value.roots.len != ownership.roots.len)
    {
        return error.KernelLimit;
    }
    try inputs(value.inputs);
    for (value.calls, 0..) |call, index| {
        try program.validation.identifier(call.id);
        try program.validation.identifier(call.library);
        try program.model.checking.text(call.interface, true);
        try program.model.checking.text(call.function, false);
        try hash(call.implementation_sha256);
        if (call.version == 0 or program.find(
            t.CallState,
            value.calls[0..index],
            call.id,
        ) != null) {
            return error.KernelState;
        }
        if (call.value) |value_| try program.value.validate(value_, .{});
    }
    for (value.roots, 0..) |root, index| {
        if (program.find(t.RootBinding, ownership.roots, root.id) == null or
            program.find(t.RootState, value.roots[0..index], root.id) != null)
        {
            return error.KernelState;
        }
        try nonce(root.generation);
        try resources(root.resources);
    }
    try @import("history.zig").validate(arena, value);
}

pub fn inputs(values: []const t.Input) Error!void {
    if (values.len > limits.program_items) return error.KernelLimit;
    for (values, 0..) |input, index| {
        try program.validation.identifier(input.id);
        if (program.find(t.Input, values[0..index], input.id) != null) return error.KernelInvalid;
        try program.value.validate(input.value, .{});
    }
}

pub fn migrationValid(value: t.Migration) Error!void {
    try program.validation.identifier(value.call);
    try program.validation.identifier(value.rule.id);
    try program.validation.identifier(value.rule.library);
    try program.model.checking.text(value.rule.interface, true);
    try program.model.checking.text(value.rule.function, false);
    try hash(value.rule.implementation_sha256);
    if (value.rule.from == 0 or value.rule.from >= value.rule.to) return error.KernelState;
}

pub fn resources(items: []const t.Resource) Error!void {
    if (items.len > limits.files_per_artifact) return error.KernelLimit;
    var bytes: u64 = 0;
    for (items, 0..) |item, index| {
        try path(item.path);
        try access.validate(item.policy);
        if (item.policy.kind != (if (item.kind == .directory) access.Kind.directory else .file)) {
            return error.KernelState;
        }
        if (index > 0 and !std.mem.lessThan(u8, items[index - 1].path, item.path)) {
            return error.KernelState;
        }
        if (item.bytes > limits.archive_entry_bytes) return error.KernelLimit;
        bytes = std.math.add(u64, bytes, item.bytes) catch return error.KernelLimit;
        if (bytes > limits.expanded_bytes) return error.KernelLimit;
        if (item.kind != .file and item.bytes != 0) return error.KernelState;
        if (item.kind != .symlink and item.link_target.len != 0) return error.KernelState;
        if (item.kind != .symlink and item.link_directory) return error.KernelState;
        if (item.kind == .symlink) try linkTarget(item.link_target);
    }
}

pub fn plan(arena: std.mem.Allocator, value: t.Plan, ownership: t.Owner) Error!void {
    if (value.schema != 2 or value.host_abi != 2) return error.KernelUnsupported;
    try nonce(value.transaction);
    if (!std.mem.eql(u8, value.instance, ownership.instance) or
        !std.mem.eql(u8, value.product_id, ownership.product_id) or
        !std.mem.eql(u8, value.state_root, ownership.state_root) or
        !sameBindings(value.roots, ownership.roots)) return error.KernelOwnership;
    if (value.previous) |previous| try snapshot(arena, previous, ownership);
    if (value.next) |next| {
        try snapshot(arena, next, ownership);
        for (next.roots) |root| {
            if (!std.mem.eql(u8, root.generation, value.transaction)) return error.KernelPlan;
        }
    } else if (value.containers.len != 0) return error.KernelPlan;
    if (value.containers.len > limits.program_items) return error.KernelLimit;
    for (value.containers) |container| {
        try program.validation.identifier(container.call);
        try program.validation.identifier(container.grant);
        if (program.find(
            t.RootBinding,
            value.roots,
            container.root,
        ) == null) return error.KernelPlan;
        if (container.prefix.len > 0) try path(container.prefix);
        if (container.container.bytes > limits.expanded_bytes) return error.KernelLimit;
        try access.validate(container.file_access);
        try access.validate(container.directory_access);
    }
}
