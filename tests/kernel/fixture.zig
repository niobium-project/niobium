//! Deterministic native-test adapter; production supplies the Component evaluator.
const std = @import("std");
const program = @import("program");
const content = @import("content");
const access = @import("access");
const platform = @import("platform");
const t = @import("kernel");
const test_digest = "0000000000000000000000000000000000000000000000000000000000000000";

pub const Fixture = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    roots: []const t.RootBinding,
    tar: []const u8,
    reference: content.ContainerRef,
    version: u32 = 1,
    empty: bool = false,
    escalate: bool = false,
    corrupt: bool = false,
    migration: bool = true,
    receipt: bool = true,
    file_policy: access.Policy = access.privatePolicy(.file),
    directory_policy: access.Policy = access.privatePolicy(.directory),
    prefix: []const u8 = "",
    evaluations: u32 = 0,

    pub fn init(arena: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, count: usize) !Fixture {
        const parent = try dir.realPathFileAlloc(io, ".", arena);
        const roots = try arena.alloc(t.RootBinding, count);
        for (roots, 0..) |*root, index| {
            const id = try arena.print("root-{d}", .{index});
            root.* = .{ .id = id, .path = try std.fs.path.join(arena, &.{ parent, id }) };
        }
        var result: Fixture = .{
            .arena = arena,
            .io = io,
            .roots = roots,
            .tar = "",
            .reference = .{ .sha256 = @splat(0), .bytes = 0 },
        };
        try result.setContent("first");
        return result;
    }

    pub fn setContent(self: *Fixture, bytes: []const u8) !void {
        var output: std.Io.Writer.Allocating = .init(self.arena);
        self.reference = try content.writeTar(
            self.arena,
            self.io,
            .{
                .entries = &.{
                    .{ .path = "bin/tool", .mode = 0o777, .body = .bytes(bytes) },
                },
            },
            &output.writer,
            .{},
        );
        self.tar = output.written();
    }

    pub fn product(self: *Fixture) t.Error!program.model.Product {
        const roots = try self.arena.alloc(program.model.Root, self.roots.len);
        const grants = try self.arena.alloc(program.model.Grant, self.roots.len);
        const grant_ids = try self.arena.alloc([]const u8, self.roots.len);
        for (self.roots, 0..) |root, index| {
            roots[index] = .{ .id = root.id };
            const id = try self.arena.print("grant-{d}", .{index});
            grants[index] = .{
                .id = id,
                .root = root.id,
                .primitive = .{ .id = "content.tree", .version = 1 },
            };
            grant_ids[index] = id;
        }
        const calls = try self.arena.alloc(program.model.Call, 1);
        calls[0] = .{
            .id = "deploy",
            .library = "library",
            .interface = "example:tool/install",
            .function = "build",
            .grants = grant_ids,
            .result_role = .plan,
            .state_version = self.version,
            .migrations = if (self.version == 2 and self.migration) &.{
                .{
                    .id = "state-v2",
                    .from = 1,
                    .to = 2,
                    .library = "library",
                    .interface = "example:tool/install",
                    .function = "migrate",
                    .implementation_sha256 = test_digest,
                },
            } else &.{},
        };
        const target: program.profile.Target = switch (@import("builtin").os.tag) {
            .macos => .@"aarch64-macos",
            .windows => .@"x86_64-windows",
            else => .@"x86_64-linux",
        };
        return .{
            .id = "kernel-example",
            .release_sequence = self.version,
            .target = target,
            .profile = .{
                .id = "test",
                .target = target,
                .primitives = &.{.{ .id = "content.tree", .version = 1 }},
            },
            .inputs = &.{
                .{
                    .id = "label",
                    .default = .{
                        .text = "default",
                    },
                    .resolved_type = .text,
                },
            },
            .libraries = &.{
                .{
                    .id = "library",
                    .member = "library.wasm",
                    .sha256 = "0000000000000000000000000000000000000000000000000000000000000000",
                    .bytes = 1,
                },
            },
            .roots = roots,
            .state_root = roots[0].id,
            .grants = grants,
            .calls = calls,
        };
    }

    pub fn options(self: *Fixture, host: *platform.Host, action: t.Action) t.Error!t.Options {
        return .{
            .io = self.io,
            .arena = self.arena,
            .model = try self.product(),
            .action = action,
            .roots = self.roots,
            .state_root = self.roots[0].id,
            .platform = host.platform(),
            .evaluator = .{ .context = self, .call = evaluate },
            .content = .{ .context = self, .open = open },
        };
    }

    fn evaluate(
        context: ?*anyopaque,
        arena: std.mem.Allocator,
        _: std.Io,
        request: t.Request,
    ) t.Error!t.EvaluationResult {
        const self: *Fixture = @ptrCast(@alignCast(context orelse return error.KernelEvaluation));
        self.evaluations += 1;
        const desired = try arena.alloc(t.DesiredContainer, if (self.empty) 0 else self.roots.len);
        for (desired, 0..) |*item, index| {
            const grant = request.model.grants[index];
            var policy = self.file_policy;
            if (self.escalate) policy.everyone.read = true;
            item.* = .{
                .call = "deploy",
                .root = grant.root,
                .grant = grant.id,
                .prefix = self.prefix,
                .container = self.reference,
                .file_access = policy,
                .directory_access = self.directory_policy,
            };
        }
        const states = try arena.alloc(t.CallResult, 1);
        states[0] = .{
            .call = "deploy",
            .value = if (self.empty) null else .{ .uint32 = self.version },
        };
        return .{
            .containers = desired,
            .states = states,
            .migrations = if (self.receipt) request.selected_migrations else &.{},
        };
    }

    fn open(
        context: ?*anyopaque,
        _: std.mem.Allocator,
        _: std.Io,
        _: content.ContainerRef,
    ) t.Error!content.Body {
        const self: *Fixture = @ptrCast(@alignCast(context orelse return error.KernelEvaluation));
        if (self.corrupt) {
            const bytes = try self.arena.dupe(u8, self.tar);
            bytes[0] ^= 1;
            return .bytes(bytes);
        }
        return .bytes(self.tar);
    }

    pub fn expectFiles(self: *Fixture, expected: []const u8) !void {
        for (self.roots) |root| {
            const path = try std.fs.path.join(
                self.arena,
                &.{
                    root.path, "current", "bin", "tool",
                },
            );
            const bytes = try std.Io.Dir.cwd().readFileAlloc(
                self.io,
                path,
                self.arena,
                .limited(
                    64,
                ),
            );
            try std.testing.expectEqualStrings(expected, bytes);
        }
    }
};
