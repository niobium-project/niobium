/* One independently compiled guest per NEGATIVE_CASE. */
#include "capability.h"

#ifndef NEGATIVE_CASE
#define NEGATIVE_CASE 1
#endif

#if NEGATIVE_CASE == 11
__attribute__((import_module("wasi_snapshot_preview1"), import_name("fd_write")))
extern void ambient_authority(void);
#endif
#if NEGATIVE_CASE == 12
NB_EXPORT("__post_instantiate") void forbidden_initializer(void) {}
#endif

static volatile unsigned char byte;
static unsigned char oversized[65537];

NB_EXPORT("nb_plan_v1") int32_t nb_plan_v1(void) {
#if NEGATIVE_CASE == 1
    for (;;) byte++;
#elif NEGATIVE_CASE == 2
    return nb_emit(99, oversized, 1);
#elif NEGATIVE_CASE == 3
    return nb_emit(0, (const void *)(uintptr_t)0xfffffff0u, 128);
#elif NEGATIVE_CASE == 4
    if (nb_emit(0, oversized, 1) < 0) return -1;
    return nb_emit(0, oversized, 1);
#elif NEGATIVE_CASE == 5
    __builtin_trap();
#elif NEGATIVE_CASE == 6
    return nb_emit(0, oversized, sizeof(oversized));
#elif NEGATIVE_CASE == 7
    for (uint32_t i = 0; i < 1025; ++i) nb_read(NB_OS, 0, oversized, 64);
    return 0;
#elif NEGATIVE_CASE == 8
    return __builtin_wasm_memory_grow(0, 17) == (uint32_t)-1 ? -1 : 0;
#elif NEGATIVE_CASE == 9
    /* Ignoring a host refusal must still fail the entire evaluation. */
    nb_emit(99, oversized, 1);
    return 0;
#elif NEGATIVE_CASE == 10
    for (uint32_t i = 0; i < 100; ++i) byte++;
    return nb_emit(0, oversized, 1);
#elif NEGATIVE_CASE == 11
    ambient_authority();
    return 0;
#elif NEGATIVE_CASE == 12
    return 0;
#else
    return -1;
#endif
}

#if NEGATIVE_CASE == 10
NB_EXPORT("nb_migrate_v1") int32_t nb_migrate_v1(uint32_t from, uint32_t to) {
    (void)from;
    (void)to;
    for (uint32_t i = 0; i < 100; ++i) byte++;
    return nb_state(oversized, 1);
}
#endif
