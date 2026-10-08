/* Test-only native fixtures. They deliberately install ACLs outside the portable subset. */
#include <stdint.h>
#include <stddef.h>
#ifdef _WIN32
#include <windows.h>
#include <aclapi.h>
int32_t nb_access_fixture_link(uintptr_t parent, const char *old_name, const char *new_name) {
    WCHAR source[2048], target[2048];
    DWORD count = GetFinalPathNameByHandleW((HANDLE)parent, source, 1024, FILE_NAME_NORMALIZED);
    if (count == 0 || count >= 1024) return 1;
    source[count++] = L'\\';
    memcpy(target, source, count * sizeof(WCHAR));
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, old_name, -1,
        source + count, 2048 - (int)count)) return 1;
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, new_name, -1,
        target + count, 2048 - (int)count)) return 1;
    return CreateHardLinkW(target, source, NULL) ? 0 : 1;
}
int32_t nb_access_fixture_inherit(uintptr_t handle, uint32_t inherit) {
    BYTE sid[SECURITY_MAX_SID_SIZE];
    DWORD length = sizeof(sid);
    union { ACL align; BYTE bytes[256]; } buffer;
    if (!CreateWellKnownSid(WinWorldSid, NULL, sid, &length)) return 1;
    if (!InitializeAcl((PACL)buffer.bytes, sizeof(buffer.bytes), ACL_REVISION)) return 1;
    if (!AddAccessAllowedAceEx((PACL)buffer.bytes, ACL_REVISION,
        inherit ? OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE : 0, FILE_ALL_ACCESS, sid)) return 1;
    return SetSecurityInfo((HANDLE)handle, SE_FILE_OBJECT,
        DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
        NULL, NULL, (PACL)buffer.bytes, NULL) == ERROR_SUCCESS ? 0 : 1;
}
int32_t nb_access_fixture_root(void) { return 0; }
#else
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
int32_t nb_access_fixture_link(uintptr_t parent, const char *old_name, const char *new_name) {
    return linkat((int)parent, old_name, (int)parent, new_name, 0) == 0 ? 0 : 1;
}
#ifdef __APPLE__
#include <sys/acl.h>
#include <grp.h>
#include <membership.h>
int32_t nb_access_fixture_inherit(uintptr_t handle, uint32_t inherit) {
    struct group *everyone = getgrnam("everyone");
    uuid_t group_id;
    if (!everyone || mbr_gid_to_uuid(everyone->gr_gid, group_id) != 0) return 1;
    acl_t acl = acl_init(1);
    if (!acl) return 1;
    acl_entry_t entry;
    acl_permset_t permissions;
    acl_flagset_t flags;
    int32_t result = 1;
    if (acl_create_entry(&acl, &entry) != 0 || acl_set_tag_type(entry, ACL_EXTENDED_ALLOW) != 0
        || acl_set_qualifier(entry, group_id) != 0 || acl_get_permset(entry, &permissions) != 0
        || acl_add_perm(permissions, ACL_READ_DATA) != 0 || acl_get_flagset_np(entry, &flags) != 0)
        goto done;
    if (inherit && (acl_add_flag_np(flags, ACL_ENTRY_FILE_INHERIT) != 0
        || acl_add_flag_np(flags, ACL_ENTRY_DIRECTORY_INHERIT) != 0)) goto done;
    if (acl_set_fd_np((int)handle, acl, ACL_TYPE_EXTENDED) == 0) result = 0;
 done:
    if (acl_free(acl) != 0) return 1;
    return result;
}
#else
#include <sys/xattr.h>
int32_t nb_access_fixture_inherit(uintptr_t handle, uint32_t inherit) {
    /* Version 2, owner/group/other rwx default ACL; identifiers are ACL_UNDEFINED_ID. */
    const uint8_t acl[] = {2,0,0,0, 1,0,7,0,255,255,255,255,
        4,0,7,0,255,255,255,255, 32,0,7,0,255,255,255,255};
    const uint8_t named[] = {2,0,0,0, 1,0,7,0,255,255,255,255,
        2,0,4,0,160,134,1,0, 4,0,0,0,255,255,255,255,
        16,0,4,0,255,255,255,255, 32,0,0,0,255,255,255,255};
    const char *name = inherit ? "system.posix_acl_default" : "system.posix_acl_access";
    if (fsetxattr((int)handle, name, inherit ? acl : named,
        inherit ? sizeof(acl) : sizeof(named), 0) == 0) return 0;
    return errno == ENOTSUP ? 3 : 1;
}
#endif
int32_t nb_access_fixture_root(void) { return geteuid() == 0 ? 1 : 0; }
#endif

#ifdef _WIN32
#include <winternl.h>
int32_t nb_access_fixture_spawn(const char *path, uint32_t *exit_code) {
    WCHAR wide[2048];
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, 2048)) return 1;
    WCHAR arguments[] = L"probe child";
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    ZeroMemory(&startup, sizeof(startup));
    ZeroMemory(&process, sizeof(process));
    startup.cb = sizeof(startup);
    if (!CreateProcessW(wide, arguments, NULL, NULL, FALSE, CREATE_NO_WINDOW,
        NULL, NULL, &startup, &process)) {
        return GetLastError() == ERROR_ACCESS_DENIED ? 2 : 1;
    }
    DWORD waited = WaitForSingleObject(process.hProcess, 10000);
    int32_t result = 0;
    if (waited != WAIT_OBJECT_0) {
        if (!TerminateProcess(process.hProcess, 124)) result = 1;
        else result = 3;
    } else {
        DWORD code;
        if (!GetExitCodeProcess(process.hProcess, &code)) result = 1;
        else *exit_code = (uint32_t)code;
    }
    BOOL thread_closed = CloseHandle(process.hThread);
    BOOL process_closed = CloseHandle(process.hProcess);
    if (!thread_closed || !process_closed) return 1;
    return result;
}
int32_t nb_access_fixture_execute(uintptr_t parent, const char *name) {
    WCHAR wide[1025];
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, wide, 1025);
    if (!count) return 1;
    UNICODE_STRING relative = {(USHORT)((count - 1) * 2), (USHORT)(count * 2), wide};
    OBJECT_ATTRIBUTES attributes;
    ZeroMemory(&attributes, sizeof(attributes));
    attributes.Length = sizeof(attributes);
    attributes.RootDirectory = (HANDLE)parent;
    attributes.ObjectName = &relative;
    attributes.Attributes = OBJ_CASE_INSENSITIVE;
    IO_STATUS_BLOCK io;
    HANDLE file;
    NTSTATUS result = NtCreateFile(&file, FILE_EXECUTE | SYNCHRONIZE, &attributes,
        &io, NULL, FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        FILE_OPEN, FILE_NON_DIRECTORY_FILE | FILE_OPEN_REPARSE_POINT |
            FILE_SYNCHRONOUS_IO_NONALERT, NULL, 0);
    if (result < 0) return RtlNtStatusToDosError(result) == ERROR_ACCESS_DENIED ? 2 : 1;
    return CloseHandle(file) ? 0 : 1;
}
#else
#include <fcntl.h>
int32_t nb_access_fixture_execute(uintptr_t parent, const char *name) {
    if (faccessat((int)parent, name, X_OK, AT_EACCESS) == 0) return 0;
    return errno == EACCES || errno == EPERM ? 2 : 1;
}
#endif
