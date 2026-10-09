# Logical content and POSIX pax container v1

- **Status:** Normative contract; qualification is recorded in [N2 acceptance](../acceptance-plan.md).
- **Decision:** [ADR-0023](../adr/0023-standard-content-and-component-contracts.md).
- **Implementation:** `libs/content`.

## Objects and identity

A logical content tree contains regular files, directories and symbolic links.
Its names describe content independently of the build host or deployment target.
Deployment validates target filesystem rules and authority separately. A valid
logical name does not authorize a host filesystem operation.

`Entry` carries a UTF-8 relative `path`, `kind`, ordinary POSIX `mode`, a borrowed
file body, and exact `link_target` text for symbolic links. `Tree.entries` is sorted
by unsigned UTF-8 bytes. Missing parent directories are synthesized with mode
`0755`; explicit empty directories and directory modes are retained. The root has
no entry. Duplicate names and children beneath a file or symbolic link fail.

`ContainerRef` is a durable value with `format = posix_pax_v1`, SHA-256 and byte
length of the canonical uncompressed tar stream. It contains no path, open file,
allocator or process handle. A normalized container and a derived container use
the same identity rule; their input references and transformation provenance are
recorded separately by the caller. Source download hashes and codec bytes do not
replace canonical identity. Changing file bytes, mode, names, empty directories
or symbolic-link text changes the canonical stream.

## Names and links

Entry names have no leading or trailing slash, empty component, `.` component,
`..` component or NUL. Invalid UTF-8 fails. Case, Unicode spelling, colons and
backslashes are preserved. This profile performs no case folding or Unicode
normalization and does not apply Windows reserved-name restrictions.

Tar ingestion removes leading `./` and a directory's trailing slash. A root
directory entry is omitted. Absolute names remain invalid.

Symbolic-link targets are relative UTF-8 text without NUL. The exact text is
preserved, including `.` and `..` components. Logical resolution must remain
inside the tree, including when traversing other symbolic links. Link expansion
is bounded by `Limits.path_components`; cycles and longer chains fail. Resolving
through a regular file fails. Dangling targets within the logical root are valid
content. Validation never follows host filesystem links.

Deployment can use `names.LinkResolver` to resolve a link through the same
bounded logical walker and obtain its final path and optional target kind. The
logical root has directory kind; a dangling target has no known kind. A backend
that requires a directory/file hint must reject unknown kind rather than guess
or inspect an ambient host path. This does not change the stored link text.

Logical link bytes and native link representation have separate identities.
Windows materialization projects `/` separators to `\` for the native link and
its native receipt; it does not collapse dot components, change case or rewrite
the logical container or frozen resource's `link_target`. POSIX materialization
uses the logical text unchanged. Readback and cleanup compare the native receipt
with the operating system's representation.

## Canonical tar profile

The stream uses 512-byte POSIX ustar headers and local pax extended headers.
Entries are sorted by normalized path. Every entry has one preceding `x` header
named `PaxHeader`. Its records are emitted in this order:

| Entry kind | Ordered pax records | Main header |
|---|---|---|
| Regular file | `path`, decimal `size` | name `entry`, type `0` |
| Directory | `path` | name `entry`, type `5`, size zero |
| Symbolic link | `path`, exact `linkpath` | name `entry`, linkname `link`, type `2`, size zero |

Pax records use the POSIX decimal byte-count syntax, including their own length
and final newline. Ustar magic/version is `ustar\0` / `00`. Numeric fields are
zero-padded octal terminated by NUL. The checksum field has six octal digits, a
NUL and a space. UID, GID and mtime are zero; owner/group names and unused fields
are zero bytes. The pax header mode is `0644`. Main-header modes preserve `0000`
through `0777`; special mode bits are unsupported. A file size beyond the ustar
field range is represented in pax with a zero main-header size.

File and pax bodies have zero padding to a 512-byte boundary. Exactly two zero
blocks finish the canonical stream. Input may contain additional zero trailer
blocks. Missing terminators, nonzero padding and data after the terminator fail.

Input accepts POSIX ustar and GNU ustar header magic, but not GNU long-name or
sparse extensions. Pax `path`, `linkpath` and `size` are honored; duplicate keys
among those three fail. UID, GID, owner/group names and timestamps are discarded.
Other pax keys fail as unsupported, including sparse, ACL and extended-attribute
metadata. Global pax headers may carry only discarded metadata. Hard links,
devices, FIFOs and other entry types are unsupported.

## API and bounded streaming

All operations receive `contracts.Limits`; filesystem reads also receive `Io`.
Arena allocations hold metadata only. The caller owns the arena and all backing
sources. The tree must not outlive its source bytes or open source files, and
the caller must keep backing content immutable while reading it.

| API | Result and ownership |
|---|---|
| `parseTar(arena, io, source, limits)` | Validated tree; payload spans borrow the seekable uncompressed source |
| `fromEntries(arena, entries, limits)` | Validated, sorted metadata snapshot with synthesized directories |
| `writeTar(arena, io, tree, writer, limits)` | Canonical stream and `ContainerRef`; reads payload in 64 KiB chunks |
| `transform(arena, tree, selection, limits)` | Filter a path prefix and remap it to another prefix |
| `merge(arena, trees, limits)` | Merge trees, coalescing equal-mode directories and rejecting other collisions |
| `freeze(io, body, writer, limits)` | Stream generated bytes to caller storage and return their byte hash and length |

`Source` is either borrowed bytes or an open file with a checked base offset and
declared logical length. File reads can carry an optional cancellation flag,
checked before each bounded read. `Body`
is a checked offset and length within a source. These are temporary in-process
views, not journal values. Parsing retains file spans without loading payloads.
Unordered input must be seekable because canonical writing sorts entries. A
codec adapter can stream decompression into bounded temporary storage, then
pass that file as a source. The content module does not require a complete tar
in memory and does not implement compression or network retrieval.

`transform` preserves file content, mode and exact link text. It revalidates
links at their new names; it never silently rewrites link text. A filter can
produce a dangling internal link. Remapping that causes escape fails. Equal
regular files at the same merged path still conflict, so caller policy chooses
which input to retain. Provenance never alters canonical identity.

The limits cover entry count, path bytes/components, individual body bytes and
total expanded/container bytes. Local pax payloads are bounded by both
`json_string_bytes` and the 64 KiB parser buffer ceiling. Metadata exhaustion
returns `OutOfMemory`; malformed, unsupported, conflicting and over-limit
inputs have distinct content errors. Input/output failures are returned without
publishing a completed identity.

## Persistence and failure

The caller writes to unpublished staging storage. A successful writer result
means bytes were accepted by its sink, not that they are durable. The caller
must flush, synchronize, close and publish storage according to its transaction
contract. No output reference is returned on failure. Partial files are caller
owned and must not become installed or cached content.

Generated content is frozen before a host plan refers to it. Its content hash
records the actual bytes; generation recipe and source hash are separate facts.
Recovery consumes the durable reference and frozen bytes and does not rerun a
generator to reproduce them.

## Validation

- `N2-CONTENT-01`: canonical identity, ordering, source metadata independence,
  UTF-8 names, exact symbolic-link spelling and empty directories.
- `N2-CONTENT-02`: parser bounds, malformed pax, unsafe links, duplicates,
  unsupported types and allocation failure propagation.
- `N2-CONTENT-03`: filtering, remapping, merge conflicts and generated snapshots.
- `N2-CONTENT-04`: file-backed payload streaming with bounded metadata memory.
- `N2-CONTENT-05`: independent GNU tar and libarchive read/write vectors.

The profile is narrower than the complete POSIX pax format. It does not claim
native bundle validity, target path compatibility, host extraction safety or
installation recovery solely because a container parses successfully.
