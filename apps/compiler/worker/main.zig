//! Process assembly for the compiler's disposable component worker.
const std = @import("std");
const worker = @import("component_worker");

pub fn main(init: std.process.Init) !void {
    try worker.serve(init.arena.allocator(), init.io);
}
