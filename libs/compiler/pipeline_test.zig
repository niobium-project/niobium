//! Shared backend contract tests; native execution and real inspector evidence use separate lanes.

const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const content = @import("content");
const image = @import("image");
const pipeline = @import("pipeline.zig");
const lock = @import("lock.zig");
const cache = @import("cache.zig");
const io = std.testing.io;

fn request(arena: std.mem.Allocator) !pipeline.Request {
    const template = try arena.dupe(u8, &image.fixture.elf());
    const library = "component-fixture";
    const inputs = try arena.dupe(pipeline.Input, &.{
        .{ .id = "runtime", .source = .{ .bytes = template } },
        .{ .id = "library", .source = .{ .bytes = library } },
    });
    const locked = try arena.dupe(lock.Input, &.{
        .{
            .id = "runtime",
            .kind = .runtime,
            .version = "1",
            .origin = "runtime",
            .sha256 = try program.digest(arena, template),
            .bytes = template.len,
            .target = .@"x86_64-linux",
        },
        .{
            .id = "library",
            .kind = .library,
            .version = "1",
            .origin = "library",
            .sha256 = try program.digest(arena, library),
            .bytes = library.len,
        },
    });
    const profile: program.profile.Profile = .{
        .id = "runtime.user",
        .target = .@"x86_64-linux",
        .primitives = &.{},
    };
    const libraries = try arena.dupe(program.model.Library, &.{.{
        .id = "library",
        .member = "libraries/library.wasm",
        .sha256 = locked[1].sha256,
        .bytes = library.len,
    }});
    return .{
        .product = .{
            .id = "sample",
            .release_sequence = 1,
            .target = .@"x86_64-linux",
            .profile = profile,
            .libraries = libraries,
            .calls = &.{.{
                .id = "exact",
                .library = "library",
                .interface = "",
                .function = "exact",
                .arguments = &.{.{ .literal = .{ .uint64 = std.math.maxInt(u64) } }},
            }},
        },
        .runtime_profile = profile,
        .inputs = inputs,
        .lock = .{ .inputs = locked },
        .runtime_id = "runtime",
        .inspector = .{ .inspect = inspect },
    };
}

fn inspect(
    _: ?*anyopaque,
    _: std.mem.Allocator,
    _: std.Io,
    _: program.model.Library,
    _: pipeline.Input,
    _: ?pipeline.Input,
) pipeline.IntegrationError!program.wit.Inspection {
    return .{ .imports = &.{}, .exports = &.{.{ .name = "exact", .item = .{ .function = .{
        .params = &.{.{ .name = "value", .ty = .uint64 }},
        .result = &.uint64,
    } } }} };
}

const imported_functions = [_]program.wit.NamedItem{.{
    .name = "facts",
    .item = .{ .function = .{ .params = &.{}, .result = &.text } },
}};

fn inspectHostImport(
    context: ?*anyopaque,
    arena: std.mem.Allocator,
    host_io: std.Io,
    library: program.model.Library,
    input: pipeline.Input,
    tool: ?pipeline.Input,
) pipeline.IntegrationError!program.wit.Inspection {
    var value = try inspect(context, arena, host_io, library, input, tool);
    value.imports = &.{.{
        .name = "niobium:host/machine@1.0.0",
        .item = .{ .instance = &imported_functions },
    }};
    return value;
}

test "N2-COMPILER-07 profile one rejects callable imports even when a host contract matches" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var value = try request(a);
    const requirement: program.profile.Requirement = .{ .id = "machine.facts", .version = 1 };
    value.product.profile.primitives = &.{requirement};
    value.runtime_profile = value.product.profile;
    const libraries = try a.dupe(program.model.Library, value.product.libraries);
    libraries[0].requires = &.{requirement};
    value.product.libraries = libraries;
    value.hosts = &.{.{
        .primitive = requirement,
        .interface = "niobium:host/machine@1.0.0",
        .functions = &imported_functions,
    }};
    value.inspector = .{ .inspect = inspectHostImport };
    var diagnostic: ?pipeline.Diagnostic = null;
    try std.testing.expectError(
        error.ContractRejected,
        pipeline.compile(a, io, value, &diagnostic),
    );
    try std.testing.expectEqual(.library, diagnostic.?.kind);
}

test "N2-COMPILER-08 unused inputs have resolved types and ambiguous or forged types reject" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var value = try request(a);
    var inputs = [_]program.model.Input{.{ .id = "unused", .default = .{ .boolean = true } }};
    value.product.inputs = &inputs;
    var diagnostic: ?pipeline.Diagnostic = null;
    const compiled = try pipeline.compile(a, io, value, &diagnostic);
    try std.testing.expect(compiled.product.inputs[0].resolved_type.? == .boolean);
    try std.testing.expect(value.product.inputs[0].resolved_type == null);
    inputs[0].default = .{ .option = null };
    try std.testing.expectError(
        error.InputTypeAmbiguous,
        pipeline.compile(a, io, value, &diagnostic),
    );
    try std.testing.expectEqual(.@"author-input", diagnostic.?.kind);
    inputs[0].default = .{ .boolean = true };
    inputs[0].resolved_type = .boolean;
    try std.testing.expectError(
        error.AuthoringResolvedType,
        pipeline.compile(a, io, value, &diagnostic),
    );
}

const channel_record: program.wit.Type = .{ .record = &.{.{
    .name = "choice",
    .ty = .{ .enumeration = &.{ "stable", "preview" } },
}} };
const other_record: program.wit.Type = .{ .record = &.{.{
    .name = "choice",
    .ty = .{ .enumeration = &.{ "stable", "nightly" } },
}} };

fn inspectInputs(
    _: ?*anyopaque,
    _: std.mem.Allocator,
    _: std.Io,
    _: program.model.Library,
    _: pipeline.Input,
    _: ?pipeline.Input,
) pipeline.IntegrationError!program.wit.Inspection {
    return .{ .imports = &.{}, .exports = &.{
        .{ .name = "select", .item = .{ .function = .{
            .params = &.{.{ .name = "input", .ty = .{ .option = &channel_record } }},
            .result = &.uint64,
        } } },
        .{ .name = "other", .item = .{ .function = .{
            .params = &.{.{ .name = "input", .ty = .{ .option = &other_record } }},
            .result = &.uint64,
        } } },
    } };
}

test "N2-COMPILER-08 nested uses preserve full enum domains and reject incompatible uses" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var value = try request(a);
    value.product.inputs = &.{.{ .id = "channel", .default = .{ .enumeration = "stable" } }};
    value.inspector = .{ .inspect = inspectInputs };
    const binding: program.model.Binding = .{ .some = &.{ .record = &.{.{
        .name = "choice",
        .binding = .{ .input = "channel" },
    }} } };
    var calls = [_]program.model.Call{
        .{
            .id = "primary",
            .library = "library",
            .interface = "",
            .function = "select",
            .arguments = &.{binding},
        },
        .{ .id = "secondary", .library = "library", .interface = "", .function = "other" },
    };
    value.product.calls = calls[0..1];
    var diagnostic: ?pipeline.Diagnostic = null;
    const compiled = try pipeline.compile(a, io, value, &diagnostic);
    const domain = compiled.product.inputs[0].resolved_type.?.enumeration;
    try std.testing.expectEqual(@as(usize, 2), domain.len);
    try std.testing.expectEqualStrings("preview", domain[1]);
    calls[1].arguments = calls[0].arguments;
    value.product.calls = &calls;
    try std.testing.expectError(error.WitTypeMismatch, pipeline.compile(a, io, value, &diagnostic));
}

fn inspectResourceResult(
    context: ?*anyopaque,
    arena: std.mem.Allocator,
    host_io: std.Io,
    library: program.model.Library,
    input: pipeline.Input,
    tool: ?pipeline.Input,
) pipeline.IntegrationError!program.wit.Inspection {
    const value = try inspect(context, arena, host_io, library, input, tool);
    const exports = try arena.dupe(program.wit.NamedItem, value.exports);
    exports[0].item.function.result = &.own_resource;
    return .{ .imports = value.imports, .exports = exports };
}

test "N2-COMPILER-09 selected resource-returning functions reject even without graph consumers" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var value = try request(a);
    value.inspector = .{ .inspect = inspectResourceResult };
    var diagnostic: ?pipeline.Diagnostic = null;
    try std.testing.expectError(error.WitTypeMismatch, pipeline.compile(a, io, value, &diagnostic));
}

test "N2-COMPILER-02 common backend verifies WIT bindings and returns source diagnostics" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var value = try request(a);
    var diagnostic: ?pipeline.Diagnostic = null;
    const compiled = try pipeline.compile(a, io, value, &diagnostic);
    try std.testing.expect(diagnostic == null);
    try std.testing.expectEqualStrings("sample", compiled.product.id);
    var calls = try a.dupe(program.model.Call, value.product.calls);
    calls[0].function = "missing";
    value.product.calls = calls;
    value.locations = &.{
        .{ .object = "call:exact", .source = .{ .file = "product.star", .line = 7, .column = 2 } },
    };
    try std.testing.expectError(
        error.WitFunctionMissing,
        pipeline.compile(a, io, value, &diagnostic),
    );
    try std.testing.expectEqualStrings("exact", diagnostic.?.object);
    try std.testing.expectEqual(.call, diagnostic.?.kind);
    try std.testing.expectEqual(@as(u32, 7), diagnostic.?.source.?.line);
    calls[0].function = "exact";
    calls[0].arguments = &.{.{ .literal = .{ .uint32 = 1 } }};
    try std.testing.expectError(error.WitTypeMismatch, pipeline.compile(a, io, value, &diagnostic));
}

test "N2-COMPILER-05 source sidecars reject ambiguous namespaces and preserve semantic identity" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var value = try request(a);
    const locations = [_]pipeline.SourceMap{
        .{ .object = "call:exact", .source = .{ .file = "a.star", .line = 2, .column = 3 } },
        .{ .object = "input:exact", .source = .{ .file = "a.star", .line = 9, .column = 1 } },
    };
    const encoded = try pipeline.source_map.encode(a, .{ .locations = &locations });
    const decoded = try pipeline.source_map.decode(a, encoded);
    var diagnostic: ?pipeline.Diagnostic = null;
    const before = try pipeline.compile(a, io, value, &diagnostic);
    value.locations = decoded.locations;
    const after = try pipeline.compile(a, io, value, &diagnostic);
    try std.testing.expectEqualStrings(before.bytes, after.bytes);
    var invalid = locations[0];
    invalid.object = "exact";
    try std.testing.expectError(error.ProgramInvalid, pipeline.source_map.entry(invalid));
    try std.testing.expectError(
        error.ProgramDuplicate,
        pipeline.source_map.validate(.{ .locations = &.{ locations[0], locations[0] } }),
    );
}

test "N2-COMPILER-02 clean warm and canceled compilation preserve verified outputs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var value = try request(a);
    value.cache = cache.Cache{ .dir = temp.dir, .io = io, .arena = a };
    var diagnostic: ?pipeline.Diagnostic = null;
    const first = try pipeline.compile(a, io, value, &diagnostic);
    const second = try pipeline.compile(a, io, value, &diagnostic);
    try std.testing.expect(!first.cache_hit);
    try std.testing.expect(second.cache_hit);
    try std.testing.expectEqualStrings(first.bytes, second.bytes);
    var cancel: std.atomic.Value(bool) = .init(true);
    value.cancel = &cancel;
    try temp.dir.writeFile(io, .{ .sub_path = "setup", .data = "old-good" });
    try std.testing.expectError(error.Canceled, pipeline.build(a, io, value, .{
        .dir = temp.dir,
        .name = "setup",
    }, &diagnostic));
    const old = try temp.dir.readFileAlloc(io, "setup", a, .limited(64));
    try std.testing.expectEqualStrings("old-good", old);
}

test "N2-COMPILER-03 raw tar identity differs from canonical embedded content" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var value = try request(a);
    var encoded: std.Io.Writer.Allocating = .init(a);
    const reference = try content.writeTar(a, io, .{ .entries = &.{.{
        .path = "data",
        .body = .bytes("hello"),
    }} }, &encoded.writer, .{});
    const raw = try a.dupe(u8, encoded.written());
    raw[114] = '1';
    @memset(raw[148..156], ' ');
    var checksum: u32 = 0;
    for (raw[0..512]) |byte| checksum += byte;
    const written = try std.fmt.bufPrint(raw[148..154], "{o:0>6}", .{checksum});
    try std.testing.expectEqual(@as(usize, 6), written.len);
    raw[154] = 0;
    value.product.containers = &.{
        .{ .id = "base", .member = "containers/base.tar", .reference = reference },
    };
    value.inputs = try std.mem.concat(a, pipeline.Input, &.{ value.inputs, &.{.{
        .id = "base",
        .source = .{ .bytes = raw },
    }} });
    value.lock.inputs = try std.mem.concat(a, lock.Input, &.{ value.lock.inputs, &.{.{
        .id = "base",
        .kind = .content,
        .version = "1",
        .origin = "raw.tar",
        .sha256 = try program.digest(a, raw),
        .bytes = raw.len,
    }} });
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var diagnostic: ?pipeline.Diagnostic = null;
    const built = try pipeline.build(
        a,
        io,
        value,
        .{ .dir = temp.dir, .name = "setup" },
        &diagnostic,
    );
    try std.testing.expect(built.bytes > raw.len);
    const setup = try temp.dir.openFile(io, "setup", .{});
    defer setup.close(io);
    const source: content.Source = .{ .file = .{ .handle = setup, .length = built.bytes } };
    const image_ref = try image.verify(a, io, source, .{});
    try std.testing.expectEqualSlices(u8, &built.program_sha256, &image_ref.program_sha256);
}
