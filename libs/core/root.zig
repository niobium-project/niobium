//! Core: assertions, crash records and phases. Depends only on std.

pub const assert = @import("assert.zig");
pub const crash = @import("crash.zig");

pub const Phase = crash.Phase;
pub const invariant = assert.invariant;

test {
    _ = assert;
    _ = crash;
}
