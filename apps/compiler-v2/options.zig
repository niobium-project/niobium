//! The compiler consumes emitted IR and explicit locked inputs; it never evaluates JSON logic.

const std = @import("std");
const contracts = @import("contracts");

pub const Error = error{ Usage, OutOfMemory };
pub const Input = struct { id: []const u8, path: []const u8 };
pub const Options = struct {
    action: enum { compile, runtime_package },
    program: ?[]const u8 = null,
    lock: ?[]const u8 = null,
    runtime: ?[]const u8 = null,
    metadata: ?[]const u8 = null,
    worker: ?[]const u8 = null,
    signer: ?[]const u8 = null,
    source_map: ?[]const u8 = null,
    output: []const u8,
    cache: ?[]const u8 = null,
    template: ?[]const u8 = null,
    target: ?[]const u8 = null,
    version: ?[]const u8 = null,
    inputs: []const Input = &.{},
};

pub fn parse(arena: std.mem.Allocator, argv: []const []const u8) Error!Options {
    if (argv.len < 2 or argv.len > 160) return error.Usage;
    const action: @FieldType(Options, "action") = if (std.mem.eql(u8, argv[1], "compile"))
        .compile
    else if (std.mem.eql(u8, argv[1], "runtime-package")) .runtime_package else return error.Usage;
    var result: Options = .{ .action = action, .output = "" };
    var inputs: std.ArrayList(Input) = .empty;
    var index: usize = 2;
    while (index < argv.len) : (index += 2) {
        if (index + 1 >= argv.len) return error.Usage;
        const name = argv[index];
        const value = argv[index + 1];
        if (value.len == 0 or value.len > contracts.limits.default.path_bytes) return error.Usage;
        if (std.mem.eql(u8, name, "--input")) {
            if (inputs.items.len >= contracts.limits.default.program_items) return error.Usage;
            const separator = std.mem.findScalar(u8, value, '=') orelse return error.Usage;
            if (separator == 0 or separator + 1 == value.len) return error.Usage;
            try inputs.append(
                arena,
                .{ .id = value[0..separator], .path = value[separator + 1 ..] },
            );
        } else if (std.mem.eql(u8, name, "--output") or std.mem.eql(u8, name, "--out")) {
            if (result.output.len != 0) return error.Usage;
            result.output = value;
        } else try option(&result, name, value);
    }
    result.inputs = inputs.items;
    if (result.output.len == 0) return error.Usage;
    if (action == .compile) {
        if (result.program == null or result.lock == null or result.runtime == null or
            result.metadata == null or result.worker == null) return error.Usage;
        if (result.template != null or result.target != null or result.version != null)
            return error.Usage;
    } else {
        if (result.template == null or result.target == null or result.version == null)
            return error.Usage;
        if (result.inputs.len != 0 or result.program != null or result.lock != null or
            result.worker != null or result.runtime != null or result.metadata != null or
            result.signer != null or result.cache != null or result.source_map != null)
            return error.Usage;
    }
    return result;
}

fn option(result: *Options, name: []const u8, value: []const u8) Error!void {
    const names = .{
        "program", "lock", "runtime", "worker", "signer", "cache", "template", "target", "version",
    };
    inline for (names) |field| {
        if (std.mem.eql(u8, name, "--" ++ field)) {
            if (@field(result, field) != null) return error.Usage;
            @field(result, field) = value;
            return;
        }
    }
    if (std.mem.eql(u8, name, "--runtime-metadata")) {
        if (result.metadata != null) return error.Usage;
        result.metadata = value;
        return;
    }
    if (std.mem.eql(u8, name, "--source-map")) {
        if (result.source_map != null) return error.Usage;
        result.source_map = value;
        return;
    }
    return error.Usage;
}

test "N2-COMPILER-04 CLI requires explicit locked identities and rejects duplicate options" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value = try parse(
        a,
        &.{
            "compiler",           "compile",
            "--program",          "product.ir",
            "--lock",             "inputs.lock",
            "--runtime",          "runtime",
            "--runtime-metadata", "metadata",
            "--worker",           "worker",
            "--input",            "worker=tool",
            "--output",           "setup",
        },
    );
    try std.testing.expectEqualStrings("worker", value.inputs[0].id);
    try std.testing.expectError(error.Usage, parse(a, &.{ "compiler", "compile" }));
    try std.testing.expectError(
        error.Usage,
        parse(
            a,
            &.{
                "compiler",     "runtime-package", "--template", "runtime", "--target",
                "x86_64-linux", "--version",       "1",          "--out",   "package.json",
                "--out",        "other.json",
            },
        ),
    );
}
