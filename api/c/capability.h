/* Niobium capability guest ABI v1. All handles belong to the current instance.
 * Only Wasm imports declared here grant authority. No WASI or libc is required.
 * read returns the full byte count or a negative error; truncation is an error.
 * emit and state copy guest bytes and return 0 or a negative error.
 */
#ifndef NIOBIUM_CAPABILITY_H
#define NIOBIUM_CAPABILITY_H
#include <stdint.h>

#define NB_CAPABILITY_ABI_V1 1u
#define NB_INPUT 1u
#define NB_OS 2u
#define NB_ARCH 3u
#define NB_PREVIOUS_STATE 4u
#define NB_ASSET 5u

#if defined(__wasm__)
#define NB_IMPORT(name) __attribute__((import_module("niobium_v1"), import_name(name)))
#define NB_EXPORT(name) __attribute__((export_name(name)))
#else
#define NB_IMPORT(name)
#define NB_EXPORT(name)
#endif

NB_IMPORT("read") int32_t nb_read(uint32_t kind, uint32_t index, void *bytes, uint32_t capacity);
NB_IMPORT("emit") int32_t nb_emit(uint32_t resource, const void *bytes, uint32_t length);
NB_IMPORT("state") int32_t nb_state(const void *bytes, uint32_t length);

/* Required export: int32_t nb_plan_v1(void).
 * Optional export: int32_t nb_migrate_v1(uint32_t from, uint32_t to).
 * Return 0 on success, negative on refusal. The host rejects any nonzero result.
 * Migration can replace state only; resource emission starts in nb_plan_v1.
 */
#endif
