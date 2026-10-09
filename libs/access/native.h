/* Private OS layout/ABI bridge. Policy decisions belong to the Zig owner. */
#ifndef NB_ACCESS_NATIVE_H
#define NB_ACCESS_NATIVE_H
#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint64_t volume;
    uint64_t inode_low;
    uint64_t inode_high;
    uint64_t filesystem;
    uint32_t mode;
    uint32_t uid;
    uint32_t gid;
    uint32_t nlink;
    uint32_t kind;
    uint32_t object_flags;
    uint32_t volume_flags;
    uint32_t acl_entries;
    uint32_t acl_flags;
    char filesystem_name[16];
} nb_access_stat;
/* Status: 0 success, 1 IO, 2 denied, 3 unsupported, 4 limit, 5 exists, 6 missing,
 * 7 no space, 8 memory, 9 wrong kind, 10 sharing/lock conflict. */
int32_t nb_access_stat_handle(uintptr_t handle, nb_access_stat *result);
int32_t nb_access_current_owner(uint8_t *buffer, uint32_t capacity, uint32_t *length);
int32_t nb_access_posix_acl(uintptr_t handle, uint32_t kind, uint32_t max_entries,
                          uint32_t *entries,
                          uint32_t *flags);
int32_t nb_access_posix_clear_acl(uintptr_t handle, uint32_t kind, uint32_t flags);
int32_t nb_access_posix_mode(uintptr_t handle, uint32_t mode);
int32_t nb_access_windows_security(uintptr_t handle, uint8_t *owner, uint32_t owner_capacity,
    uint32_t *owner_length, uint8_t *acl, uint32_t capacity, uint32_t *length, uint32_t *control);
int32_t nb_access_windows_set_acl(uintptr_t handle, const uint8_t *acl, uint32_t length,
                                 uint32_t control);
int32_t nb_access_open(uintptr_t parent, const char *name, uintptr_t *handle);
int32_t nb_access_reopen_directory(uintptr_t source, uintptr_t *handle);
int32_t nb_access_create(uintptr_t parent, const char *name, uint32_t kind,
    uint32_t mode, const uint8_t *owner, const uint8_t *acl, uintptr_t *handle);
#endif
