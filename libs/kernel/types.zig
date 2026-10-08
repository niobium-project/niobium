//! Public transaction boundary. Providers are trusted host adapters, never guest callbacks.
const std = @import("std");
const contracts = @import("contracts");
const program = @import("program");
const content = @import("content");
const access = @import("access");
const platform = @import("platform");

pub const Error = program.model.Error || content.Error || access.Error || platform.Error || error{
    KernelInvalid,
    KernelLimit,
    KernelUnsupported,
    KernelBusy,
    KernelConflict,
    KernelOwnership,
    KernelDrift,
    KernelState,
    KernelPlan,
    KernelUpgrade,
    KernelEvaluation,
};
pub const Action = enum {
    install,
    reconfigure,
    update,
    repair,
    uninstall,
    status,
    recover,

    pub fn needsProduct(self: Action) bool {
        return self != .status and self != .recover;
    }
};
pub const RootBinding = struct { id: []const u8, path: []const u8 };
pub const Input = struct { id: []const u8, value: program.value.Value };
pub const CallState = struct {
    id: []const u8,
    library: []const u8,
    interface: []const u8,
    function: []const u8,
    implementation_sha256: []const u8,
    version: u32,
    value: ?program.value.Value,
};
pub const Migration = struct { call: []const u8, rule: program.model.Migration };
pub const Resource = struct {
    path: []const u8,
    kind: content.Kind,
    sha256: contracts.Digest,
    bytes: u64,
    link_target: []const u8 = "",
    link_directory: bool = false,
    policy: access.Policy,
};
pub const RootState = struct {
    id: []const u8,
    generation: []const u8,
    resources: []const Resource,
};
pub const Snapshot = struct {
    schema: u32 = 2,
    instance: []const u8,
    product_id: []const u8,
    release_sequence: u64,
    model_version: u32,
    program_sha256: []const u8,
    inputs: []const Input,
    calls: []const CallState,
    migrations: []const Migration,
    model_migrations: []const program.Migration = &.{},
    roots: []const RootState,
};
pub const DesiredContainer = struct {
    call: []const u8,
    root: []const u8,
    grant: []const u8,
    prefix: []const u8,
    container: content.ContainerRef,
    file_access: access.Policy,
    directory_access: access.Policy,
};
pub const CallResult = struct { call: []const u8, value: ?program.value.Value };
pub const EvaluationResult = struct {
    containers: []const DesiredContainer,
    states: []const CallResult,
    /// Receipts from the trusted evaluator after it invokes the selected fixed converters.
    migrations: []const Migration = &.{},
};
pub const Request = struct {
    model: program.model.Product,
    current: ?Snapshot,
    inputs: []const Input,
    action: Action,
    selected_migrations: []const Migration,
    /// Private host workspace, alive until all generated containers have been frozen.
    workspace: std.Io.Dir,
};
pub const Evaluation = struct {
    context: ?*anyopaque = null,
    call: ?*const fn (
        ?*anyopaque,
        std.mem.Allocator,
        std.Io,
        Request,
    ) Error!EvaluationResult = null,
};
pub const ContentProvider = struct {
    context: ?*anyopaque = null,
    open: ?*const fn (
        ?*anyopaque,
        std.mem.Allocator,
        std.Io,
        content.ContainerRef,
    ) Error!content.Body = null,
};
pub const Checkpoint = struct {
    context: ?*anyopaque = null,
    call: ?*const fn (?*anyopaque, []const u8, ?[]const u8) void = null,

    pub fn reach(self: Checkpoint, name: []const u8, root: ?[]const u8) void {
        if (self.call) |callback| callback(self.context, name, root);
    }
};
pub const Options = struct {
    io: std.Io,
    arena: std.mem.Allocator,
    model: ?program.model.Product = null,
    action: Action,
    roots: []const RootBinding,
    state_root: []const u8,
    inputs: []const Input = &.{},
    evaluator: Evaluation = .{},
    content: ContentProvider = .{},
    platform: platform.Platform,
    checkpoint: Checkpoint = .{},
};
pub const Result = struct { state: ?Snapshot, recovered: bool };
pub const Owner = struct {
    schema: u32 = 2,
    instance: []const u8,
    product_id: []const u8,
    root: []const u8,
    state_root: []const u8,
    roots: []const RootBinding,
};
pub const Plan = struct {
    schema: u32 = 2,
    host_abi: u32 = 2,
    instance: []const u8,
    product_id: []const u8,
    transaction: []const u8,
    roots: []const RootBinding,
    state_root: []const u8,
    previous: ?Snapshot,
    next: ?Snapshot,
    containers: []const DesiredContainer,
};
pub const NativeReceipt = struct {
    path: []const u8,
    access_hex: []const u8 = "",
    link_inode: u128 = 0,
    link_target: []const u8 = "",
};
pub const Prepared = struct {
    schema: u32 = 2,
    plan_sha256: []const u8,
    root: []const u8,
    receipts: []const NativeReceipt,
};
