/* OS ABI/layout glue only. Grant semantics and receipt validation are implemented in Zig. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "native.h"
#include <limits.h>
#include <string.h>

#ifdef _WIN32
#include "native_windows.c"
#else
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/acl.h>
#include <sys/mount.h>
#else
#include <sys/vfs.h>
#include <sys/statvfs.h>
#include <sys/xattr.h>
#include <sys/ioctl.h>
#include <linux/fs.h>
#endif

static int32_t posix_error(int value) {
    switch (value) {
        case EACCES: case EPERM: case EROFS: return 2;
        case ENOTSUP: return 3;
        case ERANGE: case EOVERFLOW: return 4;
        case EEXIST: return 5;
        case ENOENT: return 6;
        case ENOSPC: case EDQUOT: return 7;
        case ENOMEM: return 8;
        case ELOOP: return 9;
        case EBUSY: case ETXTBSY: return 10;
        default: return 1;
    }
}

/* Zig's Linux directory handles may use O_PATH. Metadata ioctls and ACL syscalls
 * need an ordinary descriptor; reopening the same directory through its handle
 * does not resolve a caller-controlled pathname or retain ambient authority. */
static int32_t readable_handle(uintptr_t handle, int *fd, int *owned) {
    if (handle > INT_MAX) return 1;
    *fd = (int)handle;
    *owned = 0;
#ifndef __APPLE__
    int flags = fcntl(*fd, F_GETFL);
    if (flags < 0) return posix_error(errno);
    if (flags & O_PATH) {
        struct stat info;
        if (fstat(*fd, &info) != 0) return posix_error(errno);
        if (!S_ISDIR(info.st_mode)) return 3;
        *fd = openat(*fd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (*fd < 0) return posix_error(errno);
        *owned = 1;
    }
#endif
    return 0;
}

static int32_t close_readable(int fd, int owned, int32_t result) {
    if (owned && close(fd) != 0 && result == 0) return posix_error(errno);
    return result;
}

static int32_t stat_handle(uintptr_t handle, nb_access_stat *result) {
    if (handle > INT_MAX) return 1;
    struct stat info;
    struct statfs volume;
    if (fstat((int)handle, &info) != 0 || fstatfs((int)handle, &volume) != 0)
        return posix_error(errno);
    if ((uint64_t)info.st_nlink > UINT32_MAX) return 4;
    memset(result, 0, sizeof(*result));
    result->volume = (uint64_t)info.st_dev;
    result->inode_low = (uint64_t)info.st_ino;
    result->mode = (uint32_t)info.st_mode;
    result->uid = (uint32_t)info.st_uid;
    result->gid = (uint32_t)info.st_gid;
    result->nlink = (uint32_t)info.st_nlink;
    result->kind = S_ISREG(info.st_mode) ? 1 : S_ISDIR(info.st_mode) ? 2 : 0;
    result->filesystem = (uint64_t)volume.f_type;
#ifdef __APPLE__
    result->object_flags = info.st_flags;
    result->volume_flags = ((volume.f_flags & MNT_RDONLY) ? 1u : 0u)
        | ((volume.f_flags & MNT_IGNORE_OWNERSHIP) ? 2u : 0u)
        | ((volume.f_flags & MNT_NOEXEC) ? 4u : 0u)
        | ((volume.f_flags & MNT_LOCAL) ? 0u : 8u);
    memcpy(result->filesystem_name, volume.f_fstypename, sizeof(result->filesystem_name));
#else
    unsigned long file_flags = 0;
    if (ioctl((int)handle, FS_IOC_GETFLAGS, &file_flags) != 0) {
        if (errno == ENOTTY || errno == ENOTSUP) return 3;
        return posix_error(errno);
    }
    result->object_flags = (uint32_t)file_flags & (FS_IMMUTABLE_FL | FS_APPEND_FL);
    result->volume_flags = ((volume.f_flags & ST_RDONLY) ? 1u : 0u)
        | ((volume.f_flags & ST_NOEXEC) ? 4u : 0u);
#endif
    return 0;
}

int32_t nb_access_stat_handle(uintptr_t handle, nb_access_stat *result) {
    int fd, owned;
    int32_t status = readable_handle(handle, &fd, &owned);
    if (status) return status;
    status = stat_handle((uintptr_t)fd, result);
    return close_readable(fd, owned, status);
}

int32_t nb_access_current_owner(uint8_t *buffer, uint32_t capacity, uint32_t *length) {
    if (capacity < 4) return 4;
    uint32_t uid = (uint32_t)geteuid();
    for (uint32_t i = 0; i < 4; ++i) buffer[i] = (uint8_t)(uid >> (8u * i));
    *length = 4;
    return 0;
}

#ifdef __APPLE__
int32_t nb_access_posix_acl(uintptr_t handle, uint32_t kind, uint32_t max_entries,
                           uint32_t *entries, uint32_t *flags) {
    (void)kind;
    if (handle > INT_MAX) return 1;
    acl_t acl = acl_get_fd_np((int)handle, ACL_TYPE_EXTENDED);
    if (!acl) {
        if (errno == ENOENT) { *entries = 0; *flags = 0; return 0; }
        return posix_error(errno);
    }
    acl_flagset_t attributes;
    int32_t result = 0;
    *entries = 0;
    *flags = 0;
    if (acl_get_flagset_np(acl, &attributes) != 0) { result = 1; goto done; }
    if (acl_get_flag_np(attributes, ACL_FLAG_NO_INHERIT) == 1) *flags |= 1;
    if (acl_get_flag_np(attributes, ACL_FLAG_DEFER_INHERIT) == 1) *flags |= 2;
    for (uint32_t index = 0; index < max_entries; ++index) {
        acl_entry_t entry;
        if (acl_get_entry(acl, (int)index, &entry) != 0) {
            if (errno != EINVAL) result = posix_error(errno);
            goto done;
        }
        ++*entries;
        if (acl_get_flagset_np(entry, &attributes) != 0) { result = 1; goto done; }
        if (acl_get_flag_np(attributes, ACL_ENTRY_FILE_INHERIT) == 1) *flags |= 4;
        if (acl_get_flag_np(attributes, ACL_ENTRY_DIRECTORY_INHERIT) == 1) *flags |= 8;
        if (acl_get_flag_np(attributes, ACL_ENTRY_ONLY_INHERIT) == 1) *flags |= 16;
    }
    result = 4;
 done:
    if (acl_free(acl) != 0) return 1;
    return result;
}

int32_t nb_access_posix_clear_acl(uintptr_t handle, uint32_t kind, uint32_t flags) {
    (void)kind;
    if (handle > INT_MAX || flags > 1) return 1;
    acl_t acl = acl_init(0);
    if (!acl) return posix_error(errno);
    int32_t result = 0;
    if (flags) {
        acl_flagset_t attributes;
        if (acl_get_flagset_np(acl, &attributes) != 0 ||
            acl_add_flag_np(attributes, ACL_FLAG_NO_INHERIT) != 0) {
            result = 1;
            goto done;
        }
    }
    if (acl_set_fd_np((int)handle, acl, ACL_TYPE_EXTENDED) != 0) result = posix_error(errno);
 done:
    if (acl_free(acl) != 0) return 1;
    return result;
}
#else
static int32_t attribute_size(int fd, const char *name, uint32_t *length) {
    ssize_t value = fgetxattr(fd, name, NULL, 0);
    if (value < 0) {
        if (errno == ENODATA || errno == ENOTSUP) { *length = 0; return 0; }
        return posix_error(errno);
    }
    if ((uint64_t)value > UINT32_MAX) return 4;
    *length = (uint32_t)value;
    return 0;
}

static int32_t linux_acl(uintptr_t handle, uint32_t kind, uint32_t max_entries,
                           uint32_t *entries, uint32_t *flags) {
    (void)max_entries;
    if (handle > INT_MAX) return 1;
    uint32_t length = 0;
    int32_t result = attribute_size((int)handle, "system.posix_acl_access", &length);
    if (result) return result;
    *entries = length ? 1u : 0u;
    *flags = 0;
    if (kind == 2) {
        result = attribute_size((int)handle, "system.posix_acl_default", &length);
        if (result) return result;
        if (length) *flags = 4;
    }
    return 0;
}

static int32_t linux_clear_acl(uintptr_t handle, uint32_t kind, uint32_t flags) {
    if (handle > INT_MAX || flags) return 1;
    const char *names[2] = {"system.posix_acl_access", "system.posix_acl_default"};
    for (uint32_t index = 0; index < (kind == 2 ? 2u : 1u); ++index) {
        if (fremovexattr((int)handle, names[index]) != 0 && errno != ENODATA && errno != ENOTSUP)
            return posix_error(errno);
    }
    return 0;
}
int32_t nb_access_posix_acl(uintptr_t handle, uint32_t kind, uint32_t max_entries,
                           uint32_t *entries, uint32_t *flags) {
    int fd, owned;
    int32_t status = readable_handle(handle, &fd, &owned);
    if (status) return status;
    status = linux_acl((uintptr_t)fd, kind, max_entries, entries, flags);
    return close_readable(fd, owned, status);
}

int32_t nb_access_posix_clear_acl(uintptr_t handle, uint32_t kind, uint32_t flags) {
    int fd, owned;
    int32_t status = readable_handle(handle, &fd, &owned);
    if (status) return status;
    status = linux_clear_acl((uintptr_t)fd, kind, flags);
    return close_readable(fd, owned, status);
}

#endif

int32_t nb_access_posix_mode(uintptr_t handle, uint32_t mode) {
    if (handle > INT_MAX || mode > 0777) return 1;
    int fd, owned;
    int32_t status = readable_handle(handle, &fd, &owned);
    if (status) return status;
    status = fchmod(fd, (mode_t)mode) == 0 ? 0 : posix_error(errno);
    return close_readable(fd, owned, status);
}

int32_t nb_access_open(uintptr_t parent, const char *name, uintptr_t *handle) {
    if (parent > INT_MAX) return 1;
#ifdef __APPLE__
    int file = openat((int)parent, name, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC);
#else
    int file = openat((int)parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
#endif
    if (file < 0) return posix_error(errno);
    *handle = (uintptr_t)file;
    return 0;
}

int32_t nb_access_create(uintptr_t parent, const char *name, uint32_t kind,
    uint32_t mode, const uint8_t *owner, const uint8_t *acl, uintptr_t *handle) {
    (void)owner;
    (void)acl;
    if (parent > INT_MAX || mode > 0777) return 1;
    int file;
    if (kind == 1) {
        file = openat((int)parent, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                      (mode_t)mode);
    } else if (kind == 2) {
        if (mkdirat((int)parent, name, (mode_t)mode) != 0) return posix_error(errno);
        file = openat((int)parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    } else return 1;
    if (file < 0) return posix_error(errno);
    *handle = (uintptr_t)file;
    return 0;
}

int32_t nb_access_reopen_directory(uintptr_t source, uintptr_t *handle) {
    if (source > INT_MAX) return 1;
    int file = openat((int)source, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (file < 0) return posix_error(errno);
    *handle = (uintptr_t)file;
    return 0;
}
#endif
