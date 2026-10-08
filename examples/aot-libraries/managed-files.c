/* The standard managed-file capability copies its explicitly bound asset. */
#include "capability.h"

static unsigned char content[65536];

NB_EXPORT("nb_plan_v1") int32_t nb_plan_v1(void) {
    int32_t length = nb_read(NB_ASSET, 0, content, sizeof(content));
    if (length < 0) return length;
    return nb_emit(0, content, (uint32_t)length);
}
