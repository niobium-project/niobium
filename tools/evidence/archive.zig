//! Immutable R2 transport. AWS CLI owns authentication; report contents never configure it.
const std = @import("std");
const model = @import("model.zig");
const process = @import("process.zig");
const store = @import("store.zig");
pub const aws_version = "2.27.49";

pub const Client = struct {
    a: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
    endpoint: []const u8,
    bucket: []const u8,
    scratch: []const u8,

    pub fn init(context: std.process.Init) !Client {
        const a = context.arena.allocator();
        const env = context.environ_map;
        const endpoint = env.get("R2_ENDPOINT") orelse return error.MissingR2Endpoint;
        const bucket = env.get("R2_BUCKET") orelse return error.MissingR2Bucket;
        const account = std.mem.cutPrefix(u8, endpoint, "https://") orelse
            return error.InvalidR2Endpoint;
        const id = std.mem.cutSuffix(u8, account, ".r2.cloudflarestorage.com") orelse
            return error.InvalidR2Endpoint;
        if (id.len != 32 or !model.segment(bucket)) return error.InvalidR2Configuration;
        for (id) |c| if (!std.ascii.isHex(c)) return error.InvalidR2Endpoint;
        if (env.get("AWS_ACCESS_KEY_ID") == null or env.get("AWS_SECRET_ACCESS_KEY") == null)
            return error.MissingR2Credentials;
        try env.put("AWS_MAX_ATTEMPTS", "1");
        try env.put("AWS_EC2_METADATA_DISABLED", "true");
        try env.put("AWS_REQUEST_CHECKSUM_CALCULATION", "WHEN_REQUIRED");
        try env.put("AWS_RESPONSE_CHECKSUM_VALIDATION", "WHEN_REQUIRED");
        const version = try process.run(
            a,
            context.io,
            .{ .argv = &.{ "aws", "--version" }, .env = env, .timeout_ms = 10_000 },
        );
        if (version.code != 0 or
            !std.mem.startsWith(u8, version.stdout, "aws-cli/" ++ aws_version ++ " "))
            return error.WrongAwsCliVersion;
        var random: [8]u8 = undefined; // SAFETY: random fills all bytes.
        context.io.random(&random);
        const scratch = try std.fmt.allocPrint(a, ".zig-cache/evidence-{s}", .{
            std.fmt.bytesToHex(random, .lower),
        });
        try std.Io.Dir.cwd().createDirPath(context.io, scratch);
        return .{
            .a = a,
            .gpa = context.gpa,
            .io = context.io,
            .env = env,
            .endpoint = endpoint,
            .bucket = bucket,
            .scratch = scratch,
        };
    }

    pub fn invoke(c: Client, args: []const []const u8) !process.Result {
        const argv = try std.mem.concat(c.a, []const u8, &.{ &.{
            "aws",
            "--endpoint-url",
            c.endpoint,
            "--region",
            "auto",
            "--no-cli-pager",
            "--cli-connect-timeout",
            "10",
            "--cli-read-timeout",
            "60",
            "s3api",
        }, args });
        return process.run(c.a, c.io, .{ .argv = argv, .env = c.env, .timeout_ms = 120_000 });
    }

    pub fn put(c: Client, key: []const u8, bytes: []const u8) !void {
        if (bytes.len > model.limits.test_attachment_bytes) return error.ObjectTooLarge;
        const source = try std.fs.path.join(c.a, &.{ c.scratch, "upload" });
        try std.Io.Dir.cwd().writeFile(c.io, .{ .sub_path = source, .data = bytes });
        const result = try c.invoke(&.{
            "put-object",
            "--bucket",
            c.bucket,
            "--key",
            key,
            "--body",
            source,
            "--if-none-match",
            "*",
            "--storage-class",
            "STANDARD",
        });
        if (result.code != 0 and std.mem.find(
            u8,
            result.stderr,
            "PreconditionFailed",
        ) == null and std.mem.find(u8, result.stderr, "ConditionalRequestConflict") == null)
            return error.ArchiveUploadFailed;
        // Always read back: neither success nor an ETag proves the intended bytes were stored.
        const stored = try c.get(key, bytes.len);
        defer c.a.free(stored);
        try identical(bytes, stored);
    }

    fn get(c: Client, key: []const u8, size: usize) ![]const u8 {
        const target = try std.fs.path.join(c.a, &.{ c.scratch, "download" });
        const head = try c.invoke(&.{
            "head-object",
            "--bucket",
            c.bucket,
            "--key",
            key,
            "--query",
            "ContentLength",
            "--output",
            "text",
        });
        if (head.code != 0) return error.ArchiveReadbackFailed;
        const length = try std.fmt.parseInt(u64, std.mem.trim(u8, head.stdout, "\r\n "), 10);
        if (length != size) return error.ArchiveConflict;
        const range = try std.fmt.allocPrint(c.a, "bytes=0-{d}", .{size});
        const args = try std.mem.concat(c.a, []const u8, &.{
            &.{ "get-object", "--bucket", c.bucket, "--key", key },
            if (size == 0) &.{} else &.{ "--range", range },
            &.{target},
        });
        const result = try c.invoke(args);
        if (result.code != 0) return error.ArchiveReadbackFailed;
        return std.Io.Dir.cwd().readFileAlloc(
            c.io,
            target,
            c.a,
            .limited(model.limits.test_attachment_bytes),
        );
    }
};

pub fn identical(expected: []const u8, actual: []const u8) error{ArchiveConflict}!void {
    if (expected.len != actual.len or !std.mem.eql(
        u8,
        &model.digest(expected),
        &model.digest(actual),
    )) return error.ArchiveConflict;
}

pub fn publish(c: Client, path: []const u8) !void {
    var report = try store.load(c.a, c.io, path);
    if (!report.complete) {
        try store.collect(c.a, c.io, path, &report);
        try model.validate(report);
        try store.save(c.a, c.io, path, report);
    }
    var dir = try std.Io.Dir.cwd().openDir(c.io, path, .{});
    defer dir.close(c.io);
    for (report.attachments) |attachment| {
        var arena: std.heap.ArenaAllocator = .init(c.gpa);
        defer arena.deinit();
        var transfer = c;
        transfer.a = arena.allocator();
        const bytes = try store.read(
            transfer.a,
            c.io,
            dir,
            attachment.file,
            model.limits.test_attachment_bytes,
        );
        try transfer.put(attachment.key, bytes);
    }
    const key = try std.fmt.allocPrint(c.a, "reports/v1/{s}/report.json", .{
        try model.identity(c.a, report),
    });
    try c.put(key, try store.read(c.a, c.io, dir, "report.json", model.limits.test_report_bytes));
}

test "N1-AC-20 duplicate publication accepts only identical bytes" {
    try identical("saved report", "saved report");
    try std.testing.expectError(error.ArchiveConflict, identical("saved report", "changed data"));
    try std.testing.expectError(error.ArchiveConflict, identical("saved report", "saved"));
}
