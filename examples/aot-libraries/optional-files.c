/* Product policy: an optional file is absent when its boolean input is false. */
#include "capability.h"
static unsigned char input[5];
NB_EXPORT("nb_plan_v1") int32_t nb_plan_v1(void) {
    int32_t length = nb_read(NB_INPUT, 0, input, sizeof(input));
    if (length == 5 && input[0] == 'f' && input[1] == 'a' && input[2] == 'l'
        && input[3] == 's' && input[4] == 'e') return 0;
    if (length == 4 && input[0] == 't' && input[1] == 'r' && input[2] == 'u'
        && input[3] == 'e') return nb_emit(0, "enabled", 7);
    return -1;
}
