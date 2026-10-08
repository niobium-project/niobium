//! Fixed-width private bridge; native platform headers remain in native.c.
pub const Stat = extern struct {
    volume: u64,
    inode_low: u64,
    inode_high: u64,
    filesystem: u64,
    mode: u32,
    uid: u32,
    gid: u32,
    nlink: u32,
    kind: u32,
    object_flags: u32,
    volume_flags: u32,
    acl_entries: u32,
    acl_flags: u32,
    filesystem_name: [16]u8,
};
pub extern fn nb_access_stat_handle(usize, *Stat) i32;
pub extern fn nb_access_current_owner([*]u8, u32, *u32) i32;
pub extern fn nb_access_posix_acl(usize, u32, u32, *u32, *u32) i32;
pub extern fn nb_access_posix_clear_acl(usize, u32, u32) i32;
pub extern fn nb_access_posix_mode(usize, u32) i32;
pub extern fn nb_access_windows_security(usize, [*]u8, u32, *u32, [*]u8, u32, *u32, *u32) i32;
pub extern fn nb_access_windows_set_acl(usize, [*]const u8, u32, u32) i32;
pub extern fn nb_access_open(usize, [*:0]const u8, *usize) i32;
pub extern fn nb_access_reopen_directory(usize, *usize) i32;
pub extern fn nb_access_create(
    usize,
    [*:0]const u8,
    u32,
    u32,
    ?[*]const u8,
    ?[*]const u8,
    *usize,
) i32;
