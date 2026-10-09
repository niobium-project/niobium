//! C-only descriptors. Their tags and layouts are owned by api/c/compiler.h.
pub const Handle = opaque {};
pub const View = extern struct { data: ?[*]const u8 = null, len: usize = 0 };
pub const Buffer = View;
pub const Object = extern struct { owner: ?*const Handle = null, index: u32 = 0, kind: u32 = 0 };
pub fn Span(comptime T: type) type {
    return extern struct { data: ?[*]const T = null, len: usize = 0 };
}
pub const Named = extern struct { name: View, object: Object };
pub const Requirement = extern struct { id: View, version: u32 };
pub const Value = extern struct {
    tag: u32 = 0,
    flags: u32 = 0,
    unsigned_value: u64 = 0,
    signed_value: i64 = 0,
    number: f64 = 0,
    text: View = .{},
    items: Span(Object) = .{},
    fields: Span(Named) = .{},
    payload: Object = .{},
    names: Span(View) = .{},
};
pub const Binding = extern struct {
    tag: u32 = 0,
    reference: View = .{},
    projection: Span(View) = .{},
    items: Span(Object) = .{},
    fields: Span(Named) = .{},
    payload: Object = .{},
};
pub const Profile = extern struct { id: View, target: View, primitives: Span(Requirement) };
pub const Library = extern struct {
    id: View,
    member: View,
    sha256: View,
    bytes: u64,
    requires: Span(Requirement),
};
pub const Container = extern struct { id: View, member: View, sha256: View, bytes: u64 };
pub const Policy = extern struct { kind: u32, owner: u32, everyone: u32 };
pub const Grant = extern struct {
    id: View,
    root: View,
    prefix: View,
    primitive: Requirement,
    max_entries: u32,
    max_bytes: u64,
    file_access: Policy,
    directory_access: Policy,
};
pub const Observation = extern struct {
    id: View,
    function: View,
    grant: View,
    primitive: Requirement,
    arguments: Span(Object),
};
pub const Migration = extern struct {
    id: View,
    library: View,
    interface_name: View,
    function: View,
    implementation_sha256: View,
    from_version: u32,
    to_version: u32,
};
pub const Call = extern struct {
    id: View,
    library: View,
    interface_name: View,
    function: View,
    arguments: Span(Object),
    grants: Span(View),
    after: Span(View),
    state_version: u32,
    result_role: u32,
    migrations: Span(Migration),
};
