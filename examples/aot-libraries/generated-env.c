/* Independent product library. ENV_VERSION=2 includes an explicit state migration.
 * The only Niobium dependency is the public capability.h guest ABI.
 */
#include "capability.h"

#ifndef ENV_VERSION
#define ENV_VERSION 1
#endif

static unsigned char output[4096];
static unsigned char scratch[1024];
static unsigned char next_state[1024];
static uint32_t used;

static int32_t append(const unsigned char *bytes, uint32_t length) {
    if (length > sizeof(output) - used) return -1;
    for (uint32_t i = 0; i < length; ++i) output[used++] = bytes[i];
    return 0;
}

static int32_t field(const unsigned char *label, uint32_t size, uint32_t kind) {
    int32_t length = nb_read(kind, 0, scratch, sizeof(scratch));
    if (length < 0 || append(label, size) < 0) return -1;
    if (append(scratch, (uint32_t)length) < 0) return -1;
    return append((const unsigned char *)"\n", 1);
}

NB_EXPORT("nb_plan_v1") int32_t nb_plan_v1(void) {
    used = 0;
    if (field((const unsigned char *)"sdk=", 4, NB_INPUT) < 0) return -1;
    if (field((const unsigned char *)"os=", 3, NB_OS) < 0) return -1;
    if (field((const unsigned char *)"arch=", 5, NB_ARCH) < 0) return -1;
    if (field((const unsigned char *)"previous=", 9, NB_PREVIOUS_STATE) < 0) return -1;
    int32_t length = nb_read(NB_INPUT, 0, next_state + 2, sizeof(next_state) - 2);
    if (length < 0) return -1;
    next_state[0] = '0' + ENV_VERSION;
    next_state[1] = ':';
    if (nb_state(next_state, (uint32_t)length + 2) < 0) return -1;
    return nb_emit(0, output, used);
}

#if ENV_VERSION == 2
NB_EXPORT("nb_migrate_v1") int32_t nb_migrate_v1(uint32_t from, uint32_t to) {
    if (from != 1 || to != 2) return -1;
    int32_t length = nb_read(NB_PREVIOUS_STATE, 0, next_state, sizeof(next_state));
    if (length < 2 || next_state[0] != '1' || next_state[1] != ':') return -1;
    next_state[0] = '2';
    return nb_state(next_state, (uint32_t)length);
}
#endif
