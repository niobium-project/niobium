#ifndef NIOBIUM_COMPILER_H
#define NIOBIUM_COMPILER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NBC_ABI_VERSION 1
#define NBC_OK 0
#define NBC_INVALID_ARGUMENT -1
#define NBC_INVALID_PROGRAM -2
#define NBC_OUT_OF_MEMORY -3

typedef struct nbc_builder nbc_builder;
typedef struct { const uint8_t *data; size_t len; } nbc_view;
typedef struct { const uint8_t *data; size_t len; } nbc_buffer;
enum nbc_binding { NBC_INPUT = 1, NBC_ASSET = 2, NBC_RESOURCE = 3 };

/* Views are copied during calls. A builder is owned by one thread; destroy it once.
 * Every view is bounded. Empty views permit a NULL data pointer.
 * Invalid pointers and use after destroy are caller errors, as for ordinary C APIs. */
int32_t nbc_create(uint32_t abi, nbc_view product_id, uint64_t sequence,
                   uint32_t model_version, nbc_builder **out);
void nbc_destroy(nbc_builder *builder);
int32_t nbc_add_input(nbc_builder *, nbc_view id, nbc_view default_value);
int32_t nbc_add_library(nbc_builder *, nbc_view id, nbc_view wasm_bytes);
int32_t nbc_add_asset(nbc_builder *, nbc_view id, nbc_view bytes);
int32_t nbc_add_resource(nbc_builder *, nbc_view id, nbc_view relative_path);
int32_t nbc_add_instance(nbc_builder *, nbc_view id, nbc_view library, uint32_t state_version);
int32_t nbc_bind(nbc_builder *, nbc_view instance, uint32_t kind, nbc_view reference);
/* Empty owner declares a product-model migration; otherwise owner is an instance ID. */
int32_t nbc_add_migration(nbc_builder *, nbc_view owner, nbc_view id, uint32_t from, uint32_t to);
/* Emits normalized machine IR. Free its independent allocation with nbc_buffer_free. */
int32_t nbc_emit(nbc_builder *, nbc_buffer *out);
void nbc_buffer_free(nbc_buffer *buffer);
/* Borrowed static error name; do not free. Cleared by the next successful operation. */
int32_t nbc_last_error(nbc_builder *, nbc_view *out);

#ifdef __cplusplus
}
#endif
#endif
