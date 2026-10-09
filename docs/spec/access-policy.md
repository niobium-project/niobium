# Portable access policy v1

- **Status:** Normative contract; execution evidence is recorded separately under `N2-ACCESS-01`.
- **Decision:** [ADR-0023](../adr/0023-standard-content-and-component-contracts.md).
- **Owners:** `libs/access/contract` defines intent; `libs/access` implements native enforcement.

## Purpose and boundary

This profile describes discretionary access to host-owned regular files and directories.
The compiler and runtime use the same positive-rights contract. Product code does not supply
POSIX modes, Windows DACLs or inherited ACL fragments as deployment policy.

A policy does not authorize a pathname. The caller must establish namespace and object
ownership before passing a trusted directory or file handle. Matching the current OS owner
is an additional guard, not proof that an arbitrary file belongs to the product.

Content identity and native permission state are independent. Archive mode bits, owner IDs
and ACLs are source metadata; extraction does not adopt them as grants. Libraries and presets
construct an explicit deployment policy. A grant ceiling limits that policy but never becomes
an implicit request for all permitted rights.

## Policy

`Policy` contains `schema = 1`, `kind`, `owner` and `everyone`. Each rights value contains
`read`, `write` and `execute` booleans.

| Field or rule | File | Directory |
|---|---|---|
| `read` | Read content | List entry names |
| `write` | Write, append and truncate content | Create, rename and remove direct entries |
| `execute` | Native filesystem execution permission | Must be false |
| Traversal | Not applicable | Always permitted by this profile |
| Owner floor | `read = true` | `read = true` |
| Positive grants | Everyone rights are a subset of owner rights | Same |
| Dependencies | Write and execute require read | Write requires read |

The owner read floor preserves descriptor-based verification and recovery. It does not imply
that the operating systems cannot encode an owner with no rights. A local macOS test found
that an ordinary owner cannot reopen mode `000` even with `O_EVTONLY`; silently adding read
would misrepresent the requested policy. Such a policy is rejected instead.

The owner is the current effective native user, captured as a stable UID or SID. The first
profile does not transfer ownership or expose a separate group principal. On POSIX systems,
group permissions equal everyone permissions, so membership cannot change the result.
Windows uses the native Everyone SID for ordinary local access checks. Remote filesystems
and anonymous or alternate-identity execution contexts are not qualified by this profile.

The scope is future ordinary access checks. Owner control of permissions, privileged bypass,
mandatory access controls, application execution restrictions and already-open handles are
separate OS mechanisms. File write does not mean delete permission: deletion is controlled
through the containing directory's namespace rules.

Directory traversal is deliberately explicit. A directory that cannot be listed may still
lead to a known child whose own policy permits access. Restrict each child's content access;
this profile does not provide an ancestor-denial security barrier. Windows normally grants
bypass-traverse privilege, so a Unix search-bit denial would not have the same meaning.

## Native mapping

### Linux and macOS

Regular-file rights map to native `rwx` bits. Directory list and manage map to read and write;
all three classes receive search permission. Group and other bits are identical. Special mode
bits and permission-affecting immutable/append flags are outside the profile.

Existing extended ACL entries and default ACLs are not merged or discarded to make an existing
object conform. Inspection reports a conflict when the native state is outside the profile.
New Linux objects are created with restrictive modes, then inherited access/default ACLs are
removed before any content or descendants are written. The target mode is set explicitly,
independently of the caller's umask.

macOS relative creation uses `openat`/`mkdirat`, which do not accept an explicit ACL parameter.
A parent with inheritable ACL entries or deferred inheritance is rejected before creation.
A non-inheritable parent ACL is not automatically inherited. New objects receive an empty
extended ACL with inheritance disabled before content is written.

Current native implementations recognize local APFS/HFS on macOS and ext-family, XFS, Btrfs,
and tmpfs on Linux. Read-only, ownership-ignoring and remote contexts are rejected. A noexec
mount rejects a requested file execute grant. Filesystem recognition and readback are required;
a successful chmod call alone is insufficient evidence of enforcement.

### Windows

Objects have an explicit protected DACL. The owner ACE precedes an optional Everyone ACE;
all ACEs are allow ACEs without inheritance flags. The backend checks the complete DACL
against the profile's generated form. NULL DACLs, inherited or deny ACEs, unexpected principals
and extra rights are conflicts.

File read/write/execute use the corresponding file generic access masks. Directory write also
includes `FILE_DELETE_CHILD`; directory access always includes `FILE_TRAVERSE`. The owner
retains `READ_CONTROL`, `WRITE_DAC`, `FILE_READ_ATTRIBUTES` and `SYNCHRONIZE` for inspection and
maintenance. These metadata-control rights do not grant content writes.

Creation is relative to an already-open parent using `NtCreateFile` with an explicit security
descriptor. It never creates with a permissive inherited DACL and tightens it after writing.
The implementation requires a local NTFS/ReFS volume advertising persistent ACLs. Reparse
points, multiply linked files and read-only file attributes are refused. Other attributes
and security mechanisms do not become portable access policy fields.

## Native API and lifecycle

All allocating operations take a caller allocator; native operations take explicit `std.Io`.
The C bridge contains OS calls and layout conversion only. Policy validation, permission
mapping, receipt validation and lifecycle guards are Zig code. This avoids duplicating SDK
structure layouts while keeping policy independent of OS headers.

| API | Contract |
|---|---|
| `validate` | Reject unknown schema, invalid rights or an owner below the profile floor |
| `currentOwner` | Capture the effective UID/SID without account-name lookup |
| `createFile`, `createDirectory` | Exclusively create a private uncommitted object; return an open handle and observation |
| `inspect` | Read identity, ownership and supported native permission state |
| `openForAccess` | Reopen for permission recovery without requiring content write permission |
| `reopenMutableDirectory` | Reopen the same owned, currently manageable directory for final policy assignment and synchronization |
| `syncDirectory` | Flush a writable directory through an OS-authorized handle without changing or merging its ACL |
| `apply` | Check the exact prior observation and owner, apply requested policy, then read back |
| `restore` | Check current observation, require the same object/owner/kind, restore the prior native state and read back |
| `encodeReceipt`, `decodeReceipt` | Persist bounded permission records without native handles |
| `fingerprint` | Hash the encoded permission observation independently of content bytes |

The caller writes a durable intent before any native mutation. Creation is private until the
caller writes and verifies content, applies the requested access policy and publishes the
object. Every new object is exclusive; traversal components, NUL, alternate-stream syntax
and replacement of an existing name are rejected.

An error is not proof that no mutation happened. For example, creation may finish before
readback fails. Keep the uncommitted object and durable intent for recovery; do not delete a
replacement whose identity cannot be established. The enclosing filesystem transaction owns
synchronization, publication, crash recovery and completion, including metadata durability.
Permission readback by itself is not a whole-install transaction or a power-loss test.

Symlinks receive no independent access policy. Their referents retain the declared
file/directory policy; logical link identity and native link receipts follow the
[runtime lifecycle contract](runtime-lifecycle.md#desired-resources-and-frozen-content).

Linux descriptor adapters reopen `O_PATH` directories through the same handle for native
ACL, flag, mode and synchronization calls. Windows finalization retains a handle with
existing write authority while applying a read-only final policy, then flushes it before
closing. A later metadata-only reopen does not imply content write authority. The kernel
does not skip a failed flush; [Windows requires write access for `FlushFileBuffers`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers).

Permission changes have precondition and postcondition checks. Callers serialize cooperating
mutations and retain their handles. The profile does not promise a kernel compare-and-swap
against a non-cooperating owner changing permissions concurrently. Unexpected state is
reported rather than silently merged.

## Receipt

The binary envelope is little-endian: magic `NBACCESS`, schema 1, OS and object kind, rights,
owner length, volume/object identity, native-data length, owner bytes and native permission
data. Reserved bytes must be zero; lengths are checked before slicing or allocation.
The native payload is bounded by `Limits.access_acl_bytes`; ACL scans are bounded by
`Limits.access_acl_entries`. A receipt from another OS or unsupported schema is rejected.

POSIX payloads preserve mode, group ID, permission-affecting file flags, ACL flags and relevant
mount flags. Windows payloads preserve the exact supported protected DACL; the native owner
SID is stored separately. Receipts contain no process-local handle and no content digest.
They must be bound to the caller's owned resource and durable plan; they are not authorization
credentials or signed attestations.

## Errors and deferred capabilities

`AccessPolicyInvalid` rejects unsupported intent. `AccessUnsupported` rejects a filesystem
or execution context that cannot enforce the profile. `AccessConflict` rejects native ACLs,
shared inodes or permission states outside the subset. `AccessDrift` rejects a stale object or
metadata precondition. `AccessOwnerMismatch` prevents modifications through a different
owner context. Receipt syntax/version failures use `AccessReceiptInvalid`; native IO failures
retain the platform error family.

Explicit group selection, arbitrary principals, deny rules, ACL masks, inheritance templates,
recursive propagation, auditing, named-user ACLs, ownership transfer, setuid/setgid/sticky,
network filesystem qualification and merging external ACLs are deferred. The profile never
approximates one of these capabilities with a weaker grant.

## Acceptance

`tests/access` is a reusable native runner; it must execute on each claimed OS/filesystem.
Cross-compilation qualifies ABI/build coverage only. Required scenarios include:

- Rights validation, including owner-none and non-monotone grants.
- Actual denied write-open and native execute checks under an ordinary owner.
- Private creation with umask or inherited ACLs, including explicit macOS refusal.
- Readback, persisted receipt roundtrip, closing all creation handles, reopening and restore.
- Unknown ACL, stale/wrong-object receipt, malformed receipt, existing-name and hardlink refusal.
- Content unchanged by permission transitions and permission fingerprints independent of content.
- Separate native-account tests for Everyone access and denial before complete platform qualification.

## Primary references

- [Linux ACL access checks and default ACLs](https://man7.org/linux/man-pages/man5/acl.5.html).
- [Apple filesystem access control](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemDetails/FileSystemDetails.html).
- [Windows file access rights](https://learn.microsoft.com/en-us/windows/win32/fileio/file-security-and-access-rights).
- [Windows ACE ordering](https://learn.microsoft.com/en-us/windows/win32/secauthz/order-of-aces-in-a-dacl).
