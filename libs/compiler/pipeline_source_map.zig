//! Diagnostic-only source positions never enter normalized product identity or cache keys.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const types = @import("pipeline_types.zig");

pub fn validate(value: types.SourceMapFile) types.Error!void {
    if (value.schema != 1) return error.ProgramUnsupported;
    if (value.locations.len > contracts.limits.default.component_types)
        return error.ProgramLimit;
    for (value.locations, 0..) |item, index| {
        try entry(item);
        for (value.locations[0..index]) |prior| {
            if (std.mem.eql(u8, item.object, prior.object)) return error.ProgramDuplicate;
        }
    }
}

pub fn entry(item: types.SourceMap) types.Error!void {
    const separator = std.mem.findScalar(u8, item.object, ':') orelse
        return error.ProgramInvalid;
    const kind = item.object[0..separator];
    if (std.meta.stringToEnum(types.ObjectKind, kind) == null) return error.ProgramInvalid;
    try program.validation.identifier(item.object[separator + 1 ..]);
    if (item.source.file.len == 0 or
        item.source.file.len > contracts.limits.default.path_bytes or
        item.source.line == 0 or item.source.column == 0) return error.ProgramInvalid;
    if (!std.unicode.utf8ValidateSlice(item.source.file) or
        std.mem.findScalar(u8, item.source.file, 0) != null) return error.ProgramInvalid;
}

pub fn decode(arena: std.mem.Allocator, bytes: []const u8) types.Error!types.SourceMapFile {
    const value = try contracts.json.decode(types.SourceMapFile, arena, bytes, .{
        .max_bytes = contracts.limits.default.program_bytes,
        .max_schema = 1,
    });
    try validate(value);
    return value;
}

pub fn encode(arena: std.mem.Allocator, value: types.SourceMapFile) types.Error![]const u8 {
    try validate(value);
    const buffer = try arena.alloc(u8, contracts.limits.default.program_bytes);
    var writer: std.Io.Writer = .fixed(buffer);
    std.json.Stringify.value(value, .{}, &writer) catch return error.ProgramLimit;
    return buffer[0..writer.end];
}
