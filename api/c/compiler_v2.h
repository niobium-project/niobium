#ifndef NIOBIUM_COMPILER_V2_H
#define NIOBIUM_COMPILER_V2_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define NBC2_ABI_VERSION 2
#define NBC2_OK 0
#define NBC2_INVALID_ARGUMENT -1
#define NBC2_INVALID_PROGRAM -2
#define NBC2_OUT_OF_MEMORY -3

typedef struct nbc2_builder nbc2_builder;
typedef struct { const uint8_t *data; size_t len; } nbc2_view;
typedef struct { const uint8_t *data; size_t len; } nbc2_buffer;
typedef struct { const nbc2_builder *owner; uint32_t index; uint32_t kind; } nbc2_object;
typedef struct { const nbc2_object *data; size_t len; } nbc2_objects;
typedef struct { const nbc2_view *data; size_t len; } nbc2_views;
typedef struct { nbc2_view name; nbc2_object object; } nbc2_named;
typedef struct { const nbc2_named *data; size_t len; } nbc2_fields;
typedef struct { nbc2_view id; uint32_t version; } nbc2_requirement;
typedef struct { const nbc2_requirement *data; size_t len; } nbc2_requirements;
/* Tags are stable ABI values, independent of Zig/JSON tag order. */
enum nbc2_value_tag {
 NBC2_BOOL=1, NBC2_U8, NBC2_U16, NBC2_U32, NBC2_U64,
 NBC2_S8, NBC2_S16, NBC2_S32, NBC2_S64, NBC2_F32, NBC2_F64,
 NBC2_CHAR, NBC2_TEXT, NBC2_BYTES, NBC2_LIST, NBC2_TUPLE,
 NBC2_RECORD, NBC2_VARIANT, NBC2_ENUM, NBC2_OPTION, NBC2_RESULT, NBC2_FLAGS
};
typedef struct {
 uint32_t tag, flags;
 uint64_t unsigned_value;
 int64_t signed_value;
 double number;
 nbc2_view text;
 nbc2_objects items;
 nbc2_fields fields;
 nbc2_object payload;
 nbc2_views names;
} nbc2_value_desc;
enum nbc2_binding_tag {
 NBC2_LITERAL=1, NBC2_INPUT, NBC2_NODE_RESULT, NBC2_OBSERVATION, NBC2_PREVIOUS_STATE,
 NBC2_RECORD_BINDING, NBC2_LIST_BINDING, NBC2_TUPLE_BINDING, NBC2_SOME_BINDING
};
typedef struct {
 uint32_t tag;
 nbc2_view reference;
 nbc2_views projection;
 nbc2_objects items;
 nbc2_fields fields;
 nbc2_object payload;
} nbc2_binding_desc;
typedef struct { nbc2_view id, target; nbc2_requirements primitives; } nbc2_profile;
typedef struct {
 nbc2_view id, member, sha256;
 uint64_t bytes;
 nbc2_requirements requires;
} nbc2_library;
/* Library sha256 is lowercase hex; container sha256 is exactly 32 binary bytes. */
typedef struct { nbc2_view id, member, sha256; uint64_t bytes; } nbc2_container;
/* Positive access bits: read=1, write=2, execute=4; directory execute is invalid. */
typedef struct { uint32_t kind, owner, everyone; } nbc2_policy;
typedef struct {
 nbc2_view id, root, prefix;
 nbc2_requirement primitive;
 uint32_t max_entries;
 uint64_t max_bytes;
 nbc2_policy file_access, directory_access;
} nbc2_grant;
typedef struct {
 nbc2_view id, function, grant;
 nbc2_requirement primitive;
 nbc2_objects arguments;
} nbc2_observation;
typedef struct {
 nbc2_view id, library, interface_name, function, implementation_sha256;
 uint32_t from_version, to_version;
} nbc2_migration;
typedef struct { const nbc2_migration *data; size_t len; } nbc2_migrations;
typedef struct {
 nbc2_view id, library, interface_name, function;
 nbc2_objects arguments;
 nbc2_views grants, after;
 uint32_t state_version, result_role; /* value=0, plan=1 */
 nbc2_migrations migrations;
} nbc2_call;
/* Builders and objects are single-thread owned. Constructors copy views and spans.
 * Object handles live until their builder is destroyed; no individual free is needed.
 * Cross-builder and wrong-kind handles fail. Zero object means absent optional payload.
 * Valid pointer lifetimes and no use after destroy are C caller responsibilities.
 * Zero-initialize descriptors. Unused descriptor fields are ignored. Bool uses flags 0/1;
 * result uses flags 1=ok,0=error; optional/variant/result payload uses a zero handle for none.
 * Profiles name an explicit target: x86_64-windows, aarch64-macos, x86_64-linux.
 * String views are UTF-8; bytes are opaque. All spans and aggregate depth are bounded.
 */
int32_t nbc2_create(uint32_t abi, nbc2_view id, uint64_t release, uint32_t model_version,
                    const nbc2_profile *, nbc2_builder **out);
void nbc2_destroy(nbc2_builder *);
int32_t nbc2_value(nbc2_builder *, const nbc2_value_desc *, nbc2_object *out);
int32_t nbc2_binding(nbc2_builder *, const nbc2_binding_desc *, nbc2_object *out);
int32_t nbc2_input(nbc2_builder *, nbc2_view id, nbc2_object value);
int32_t nbc2_library_add(nbc2_builder *, const nbc2_library *);
int32_t nbc2_container_add(nbc2_builder *, const nbc2_container *);
int32_t nbc2_root(nbc2_builder *, nbc2_view id, uint32_t scope); /* user=1, machine=2 */
int32_t nbc2_state_root(nbc2_builder *, nbc2_view id);
int32_t nbc2_grant_add(nbc2_builder *, const nbc2_grant *);
int32_t nbc2_observe(nbc2_builder *, const nbc2_observation *);
int32_t nbc2_call_add(nbc2_builder *, const nbc2_call *);
int32_t nbc2_upgrade(nbc2_builder *, nbc2_view id, uint32_t from, uint32_t to);
/* Emission normalizes and validates the common model. Buffer outlives its builder. */
int32_t nbc2_emit(nbc2_builder *, nbc2_buffer *out);
/* Diagnostic sidecar keys are qualified, e.g. call:configure. Replaces an existing key.
 * Positions are one-based and never affect semantic model bytes or compiler cache identity. */
int32_t nbc2_location(nbc2_builder *, nbc2_view object, nbc2_view file,
                     uint32_t line, uint32_t column);
int32_t nbc2_emit_source_map(nbc2_builder *, nbc2_buffer *out);
void nbc2_buffer_free(nbc2_buffer *);
/* Borrowed static diagnostic; next successful operation clears it. */
int32_t nbc2_last_error(nbc2_builder *, nbc2_view *out);
#ifdef __cplusplus
}
#endif
#endif
