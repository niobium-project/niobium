//! Private C bridge to WAMR; public guest ABI is api/c/capability.h.
pub const Request = extern struct {
    context: *anyopaque,
    read: *const fn (*anyopaque, u32, u32, [*]u8, u32) callconv(.c) i32,
    write: *const fn (*anyopaque, u32, [*]const u8, u32) callconv(.c) i32,
    phase: *const fn (*anyopaque, u32) callconv(.c) void,
    heap: *anyopaque,
    heap_size: u32,
    stack_size: u32,
    instructions: i32,
    migrate: u32,
    from: u32,
    to: u32,
};
pub extern fn nb_wamr_evaluate([*]u8, u32, *const Request) i32;
