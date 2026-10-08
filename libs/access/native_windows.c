/* Windows declarations/layout stay in the SDK. This file performs no policy selection. */
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0602
#endif
#include <windows.h>
#include <winternl.h>
#include <aclapi.h>

static int32_t win_error(DWORD value) {
    switch (value) {
        case ERROR_ACCESS_DENIED: case ERROR_PRIVILEGE_NOT_HELD:
        case ERROR_INVALID_OWNER: return 2;
        case ERROR_NOT_SUPPORTED: case ERROR_INVALID_FUNCTION: return 3;
        case ERROR_INSUFFICIENT_BUFFER: case ERROR_BUFFER_OVERFLOW: return 4;
        case ERROR_FILE_EXISTS: case ERROR_ALREADY_EXISTS: return 5;
        case ERROR_FILE_NOT_FOUND: case ERROR_PATH_NOT_FOUND: return 6;
        case ERROR_DISK_FULL: case ERROR_HANDLE_DISK_FULL: return 7;
        case ERROR_NOT_ENOUGH_MEMORY: case ERROR_OUTOFMEMORY: return 8;
        case ERROR_SHARING_VIOLATION: case ERROR_LOCK_VIOLATION: return 10;
        default: return 1;
    }
}

int32_t nb_access_stat_handle(uintptr_t handle, nb_access_stat *result) {
    HANDLE file = (HANDLE)handle;
    BY_HANDLE_FILE_INFORMATION info;
    WCHAR name[16];
    DWORD flags, maximum;
    IO_STATUS_BLOCK io;
    FILE_FS_DEVICE_INFORMATION device;
    if (!GetFileInformationByHandle(file, &info)) return win_error(GetLastError());
    if (!GetVolumeInformationByHandleW(file, NULL, 0, NULL, &maximum, &flags, name, 16))
        return win_error(GetLastError());
    NTSTATUS status = NtQueryVolumeInformationFile(file, &io, &device,
        sizeof(device), FileFsDeviceInformation);
    if (status < 0) return win_error(RtlNtStatusToDosError(status));
    memset(result, 0, sizeof(*result));
    result->volume = info.dwVolumeSerialNumber;
    result->inode_low = ((uint64_t)info.nFileIndexHigh << 32) | info.nFileIndexLow;
    result->nlink = info.nNumberOfLinks;
    result->kind = (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? 2 : 1;
    result->object_flags = info.dwFileAttributes;
    result->volume_flags = ((flags & FILE_READ_ONLY_VOLUME) ? 1u : 0u)
        | ((device.Characteristics & 0x10u) ? 8u : 0u)
        | ((flags & FILE_PERSISTENT_ACLS) ? 16u : 0u);
    for (uint32_t i = 0; i < 16; ++i) {
        if (name[i] > 127) return 3;
        result->filesystem_name[i] = (char)name[i];
        if (name[i] == 0) return 0;
    }
    return 4;
}

int32_t nb_access_current_owner(uint8_t *buffer, uint32_t capacity, uint32_t *length) {
    HANDLE token;
    if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &token)) {
        if (GetLastError() != ERROR_NO_TOKEN) return win_error(GetLastError());
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
            return win_error(GetLastError());
    }
    union { TOKEN_USER align; BYTE bytes[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE]; } storage;
    DWORD used;
    int32_t result = 0;
    if (!GetTokenInformation(token, TokenUser, storage.bytes, sizeof(storage.bytes), &used)) {
        result = win_error(GetLastError());
    } else {
        TOKEN_USER *user = (TOKEN_USER *)storage.bytes;
        if (!IsValidSid(user->User.Sid)) result = 1;
        else {
            DWORD size = GetLengthSid(user->User.Sid);
            if (size > capacity) result = 4;
            else { memcpy(buffer, user->User.Sid, size); *length = size; }
        }
    }
    if (!CloseHandle(token)) return 1;
    return result;
}

int32_t nb_access_windows_security(uintptr_t handle, uint8_t *owner, uint32_t owner_capacity,
    uint32_t *owner_length, uint8_t *acl, uint32_t capacity, uint32_t *length, uint32_t *control) {
    PSID sid = NULL;
    PACL dacl = NULL;
    PSECURITY_DESCRIPTOR descriptor = NULL;
    DWORD error = GetSecurityInfo((HANDLE)handle, SE_FILE_OBJECT,
        OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
        &sid, NULL, &dacl, NULL, &descriptor);
    if (error != ERROR_SUCCESS) return win_error(error);
    int32_t result = 0;
    SECURITY_DESCRIPTOR_CONTROL bits;
    DWORD revision;
    if (!IsValidSid(sid) || !GetSecurityDescriptorControl(descriptor, &bits, &revision)) {
        result = 1;
    } else {
        DWORD sid_size = GetLengthSid(sid);
        DWORD acl_size = dacl ? dacl->AclSize : 0;
        if (sid_size > owner_capacity || acl_size > capacity) result = 4;
        else if (dacl && !IsValidAcl(dacl)) result = 1;
        else {
            memcpy(owner, sid, sid_size);
            if (acl_size) memcpy(acl, dacl, acl_size);
            *owner_length = sid_size;
            *length = acl_size;
            *control = (bits & SE_DACL_PROTECTED) ? 1u : 0u;
        }
    }
    if (LocalFree(descriptor) != NULL) return 1;
    return result;
}

int32_t nb_access_windows_set_acl(uintptr_t handle, const uint8_t *acl, uint32_t length,
                                 uint32_t control) {
    if (length < sizeof(ACL) || control != 1 || !IsValidAcl((PACL)acl)) return 1;
    if (((PACL)acl)->AclSize != length) return 1;
    DWORD error = SetSecurityInfo((HANDLE)handle, SE_FILE_OBJECT,
        DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
        NULL, NULL, (PACL)acl, NULL);
    return error == ERROR_SUCCESS ? 0 : win_error(error);
}

static int32_t open_relative(uintptr_t parent, const char *name, uint32_t kind,
    PSECURITY_DESCRIPTOR descriptor, uintptr_t *handle) {
    WCHAR wide[1025];
    int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, wide, 1025);
    if (!size) return win_error(GetLastError());
    UNICODE_STRING relative = {(USHORT)((size - 1) * sizeof(WCHAR)),
        (USHORT)(size * sizeof(WCHAR)), wide};
    OBJECT_ATTRIBUTES attributes;
    memset(&attributes, 0, sizeof(attributes));
    attributes.Length = sizeof(attributes);
    attributes.RootDirectory = (HANDLE)parent;
    attributes.ObjectName = &relative;
    attributes.Attributes = OBJ_CASE_INSENSITIVE;
    attributes.SecurityDescriptor = descriptor;
    IO_STATUS_BLOCK io;
    HANDLE file;
    ACCESS_MASK access = descriptor ? FILE_GENERIC_READ | FILE_GENERIC_WRITE | WRITE_DAC
        : READ_CONTROL | WRITE_DAC | FILE_READ_ATTRIBUTES | SYNCHRONIZE;
    ULONG kind_flag = kind == 0 ? 0 : kind == 2 ? FILE_DIRECTORY_FILE : FILE_NON_DIRECTORY_FILE;
    NTSTATUS result = NtCreateFile(&file, access, &attributes, &io, NULL, FILE_ATTRIBUTE_NORMAL,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        descriptor ? FILE_CREATE : FILE_OPEN,
        FILE_OPEN_REPARSE_POINT | FILE_SYNCHRONOUS_IO_NONALERT | kind_flag, NULL, 0);
    if (result < 0) return win_error(RtlNtStatusToDosError(result));
    *handle = (uintptr_t)file;
    return 0;
}

int32_t nb_access_create(uintptr_t parent, const char *name, uint32_t kind,
    uint32_t mode, const uint8_t *owner, const uint8_t *acl, uintptr_t *handle) {
    (void)mode;
    if (kind != 1 && kind != 2) return 1;
    SECURITY_DESCRIPTOR descriptor;
    if (!InitializeSecurityDescriptor(&descriptor, SECURITY_DESCRIPTOR_REVISION)
        || !SetSecurityDescriptorOwner(&descriptor, (PSID)owner, FALSE)
        || !SetSecurityDescriptorDacl(&descriptor, TRUE, (PACL)acl, FALSE)
        || !SetSecurityDescriptorControl(&descriptor, SE_DACL_PROTECTED, SE_DACL_PROTECTED))
        return win_error(GetLastError());
    return open_relative(parent, name, kind, &descriptor, handle);
}

int32_t nb_access_open(uintptr_t parent, const char *name, uintptr_t *handle) {
    return open_relative(parent, name, 0, NULL, handle);
}

int32_t nb_access_reopen_directory(uintptr_t source, uintptr_t *handle) {
    WCHAR dot[] = L".";
    /* An empty relative name reopens the object held by RootDirectory. */
    UNICODE_STRING relative = {0, sizeof(dot), dot};
    OBJECT_ATTRIBUTES attributes;
    memset(&attributes, 0, sizeof(attributes));
    attributes.Length = sizeof(attributes);
    attributes.RootDirectory = (HANDLE)source;
    attributes.ObjectName = &relative;
    attributes.Attributes = OBJ_CASE_INSENSITIVE;
    IO_STATUS_BLOCK io;
    HANDLE directory;
    NTSTATUS result = NtCreateFile(&directory,
        FILE_GENERIC_READ | FILE_GENERIC_WRITE | WRITE_DAC, &attributes, &io, NULL,
        FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        FILE_OPEN, FILE_DIRECTORY_FILE | FILE_OPEN_REPARSE_POINT |
            FILE_SYNCHRONOUS_IO_NONALERT, NULL, 0);
    if (result < 0) return win_error(RtlNtStatusToDosError(result));
    *handle = (uintptr_t)directory;
    return 0;
}
