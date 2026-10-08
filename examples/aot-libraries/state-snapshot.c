/* Writing a result does not change the previous-state observation of this phase. */
#include "capability.h"
static unsigned char previous[64];
NB_EXPORT("nb_plan_v1") int32_t nb_plan_v1(void) {
    if (nb_state("new", 3) < 0) return -1;
    int32_t count = nb_read(NB_PREVIOUS_STATE, 0, previous, sizeof(previous));
    if (count < 0) return count;
    return nb_emit(0, previous, (uint32_t)count);
}
