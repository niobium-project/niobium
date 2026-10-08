//! A Zig guest uses the same versioned ABI as the C standard capability library.
const capability = @import("capability_sdk");

export fn nb_plan_v1() i32 {
    var buffer: [65536]u8 = undefined; // SAFETY: read returns only the initialized prefix.
    const bytes = capability.read(.asset, 0, &buffer) catch return -1;
    capability.emit(0, bytes) catch return -1;
    return 0;
}
