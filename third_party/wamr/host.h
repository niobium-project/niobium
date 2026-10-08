/* Niobium's private bridge to the pinned interpreter. Not a guest ABI. */
#ifndef NB_WAMR_HOST_H
#define NB_WAMR_HOST_H
#include <stdint.h>
typedef int32_t (*nb_wamr_read)(void *, uint32_t, uint32_t, uint8_t *, uint32_t);
typedef int32_t (*nb_wamr_write)(void *, uint32_t, const uint8_t *, uint32_t);
typedef struct {
    void *context;
    nb_wamr_read read;
    nb_wamr_write write;
    void (*phase)(void *, uint32_t);
    void *heap;
    uint32_t heap_size;
    uint32_t stack_size;
    int32_t instructions;
    uint32_t migrate;
    uint32_t from;
    uint32_t to;
} nb_wamr_request;
/* 0 success, 1 initialization, 2 invalid module, 3 trap, 4 refusal, 5 ABI. */
int32_t nb_wamr_evaluate(uint8_t *, uint32_t, const nb_wamr_request *);
#endif
