# Native setup image v2

- **Status:** Normative contract; native qualification is recorded in [N2 acceptance](../acceptance-plan-v0.2.md).
- **Decision:** [ADR-0023](../adr/0023-standard-content-and-component-contracts.md).
- **Implementation:** `libs/image`.

## Assembly boundary

Product assembly consumes a complete precompiled runtime template, compiled
program bytes and a [content container](content-container-v1.md). It produces a
native executable without executing, recompiling or relinking the runtime.
The build host does not need the target SDK. Runtime release builds and final
target execution qualification are separate operations.

The image layer treats program and payload bytes as opaque streams. Program
schema validation, capability binding, content conformance and publisher trust
remain their owners' responsibilities. Embedding a byte sequence does not
declare it a valid program, content container or trusted library.

The native template contains a 256-byte reserved descriptor:

| Format | Target profile | Descriptor location |
|---|---|---|
| ELF | ELF64 little-endian, x86_64 or aarch64 | allocated `.nbprod` section |
| PE | PE32+ x86_64 or aarch64 | `.nbprod`, virtual size 256; raw padding is retained |
| Mach-O | thin Mach-O64 executable, x86_64 or arm64 | `__DATA,__nbproduct`, size 256 |

These parser profiles do not establish runtime support for every listed target.
Qualified runtime packages and real-OS evidence determine supported execution.
Universal Mach-O, ELF32 and PE32 are outside this format version.

## Descriptor and byte ranges

All integers are little-endian. An unbound template uses magic `NIOTMP02`,
version 2 and descriptor length 256. Bytes 200..204 contain the mandatory
little-endian native-prefix profile marker 1; all other fields are zero. Templates
without this marker are rejected before product assembly, including older
pre-release v2 runtimes that cannot validate the measured descriptor. A
bound image uses `NIOIMG02` and the following fields:

| Offset | Length | Field |
|---|---|---|
| 0 | 8 | Magic |
| 8 | 4 | Version, exactly 2 |
| 12 | 4 | Descriptor length, exactly 256 |
| 16 | 8 | Original captured template byte length |
| 24 | 8 | Compiled program file offset |
| 32 | 8 | Compiled program byte length |
| 40 | 8 | Content payload file offset |
| 48 | 8 | Content payload byte length |
| 56 | 8 | Reserved zero bytes |
| 64 | 32 | SHA-256 of the captured complete runtime template |
| 96 | 32 | SHA-256 of embedded program bytes |
| 128 | 32 | SHA-256 of embedded content bytes |
| 160 | 8 | Retained native prefix length before program alignment |
| 168 | 32 | Native prefix measurement SHA-256 |
| 200 | 4 | Native prefix measurement profile, exactly 1 |
| 204 | 52 | Reserved zero bytes |

The program starts at the retained prefix length rounded up to 16 bytes. Content
starts after the program, rounded up to 16 bytes. Alignment gaps contain zeros.
This descriptor references ordinary native sections and standard content bytes;
it introduces no archive member encoding.

### Native prefix measurement profile 1

The assembler measures the retained native prefix from its captured template
before any product or signing edits. The SHA-256 input begins with the bytes
`niobium.native-prefix\0`, the format tag (`elf`, `pe`, or `macho`), NUL, the CPU
tag (`x86_64` or `aarch64`), NUL, profile 1 as a little-endian u32, and the retained
prefix length as a little-endian u64. It then includes every byte in
`[0, prefix_bytes)`, with only these ranges replaced by zeros:

- The complete 256-byte product descriptor slot.
- PE: the 4-byte checksum and 8-byte security data-directory entry.
- Mach-O: the 8-byte `LC_CODE_SIGNATURE` data offset/size, and the 8-byte
  `__LINKEDIT` virtual size and 8-byte file size.

Header masks must remain inside validated native headers. All masks must be
bounded by the measured prefix, mutually disjoint and outside executable code
sections. The slot must not overlap native tables or headers. Code, data, import
metadata and all other prefix bytes remain measured. Streaming verification uses
the same profile after assembly and final signing. Unknown measurement profiles
fail closed.

Masked fields remain structurally constrained. The `__LINKEDIT` file range must
end at the image end, its virtual range must follow all other segments, and its
virtual size must equal its file size rounded up to either 4 KiB or 16 KiB.
Zero, undersized and arbitrary larger reservations are rejected. The qualified
Zig templates and signing tools currently produce the 16 KiB form; accepting
these bounded carrier forms does not replace target-OS execution qualification.

The complete captured-template SHA-256 remains a separate publication identity;
the native-prefix digest permits only the documented assembly/signature changes.
The runtime compares the captured descriptor with its already loaded descriptor
before trusting product metadata, then verifies this prefix measurement. A
replacement file cannot retain the loaded descriptor while substituting native
code, data or import metadata. This integrity boundary does not authenticate a
publisher or replace platform signature verification.

Parsers reject missing/duplicate descriptor sections, executable descriptors,
overlap with native headers/tables/code, unsupported versions, nonzero reserved
bytes, overflowing ranges and references into native data. Payloads must end
before native signatures. ELF has no unreferenced trailer; PE and Mach-O allow
only their bounded alignment padding followed by the native certificate/signature
region. Product lookup never assumes data resides at EOF.

## Native transformations

ELF retains its complete native prefix, including section and program tables.
Program and content bytes are appended; ELF headers are unchanged.

PE retains all sections and native tables. A terminal Authenticode certificate
table is removed when consuming a signed template, and the certificate directory
and checksum are cleared. Product bytes precede any subsequent Authenticode
signature. Nonterminal certificate tables are unsupported.

Mach-O requires a final `__LINKEDIT` segment and terminal `LC_CODE_SIGNATURE`.
The existing signature is moved after the appended program/content, aligned to
16 bytes. `LC_CODE_SIGNATURE.dataoff`, `__LINKEDIT.filesize` and
`__LINKEDIT.vmsize` are adjusted; no executable section moves or changes. Virtual
size is rounded up to 16 KiB. File offsets remain bounded by the native 32-bit
signature-offset field even when the general image limit is larger.

The moved Mach-O signature is stale. This intermediate must be finalized by a
signer before executable qualification. Removing its signature command values
without providing a structurally valid signature location is not the supported
assembly operation. Only the final signer determines final signature bytes.

Every backend rejects writable executable regions and bounds section/load-command
counts. The Mach-O profile accepts a stated set of load commands and accounts
for their symbol, relocation and link-edit data ranges. Unknown load commands
fail explicitly. This parser does not substitute for the platform loader or
publisher signature verifier.

## API, snapshots and publication

`assemble(arena, io, template, program, payload, output, limits)` requires a new,
empty, read/write output file. It copies the complete template once while hashing
the actual copied bytes, then inspects that captured snapshot. It never returns
to the original template source for later assembly reads. A terminal Mach-O
signature is moved with backwards bounded copying so overlapping moves are safe.
Program and content are copied while calculating their actual byte hashes.

The result reports the descriptor, format, CPU, byte length and whether native
signing is required. The compiler must compare the returned template identity
with its lock before publication. A source changing during capture cannot be
mistaken for the previously locked identity. Caller-owned output staging must
remain private and unchanged during assembly and finalization.

`inspect` validates native layout, descriptor ranges and zero padding. `verify`
also checks the native-prefix measurement and streams and compares program/content
SHA-256 values. These checks establish
internal consistency; self-declared hashes are not publisher authentication.
The original template digest requires a trusted runtime package/lock to establish
provenance. Final signing, timestamping and notarization have their own identities.

Payload transfers use 64 KiB buffers. Metadata allocation is bounded by native
section counts. `Limits.native_image_bytes` bounds images, `native_header_bytes`
bounds relevant header data, and `native_sections` bounds native collections.
The image layer has no 1 MiB payload limit and does not allocate complete images.

Failures return errors and leave caller-owned unpublished output. The caller must
close/remove failed staging files, synchronize successful output, finalize the
chosen signature profile and atomically publish according to its build contract.
The image layer never replaces an existing destination or claims a partial file
is executable-qualified.

## Signing and qualification

Linux-hosted signing can use pinned `rcodesign` for Mach-O and `osslsigncode` for
PE. Apple notarization can use the Notary REST API. These are build-host tools;
the native image assembler does not invoke them. Native signature validity,
publisher identity, notarization and target execution are separate results.

Apple Silicon requires a valid code signature; an ad-hoc signature is sufficient
for that code-loading requirement. It does not establish Developer ID trust or
default Gatekeeper acceptance. A custom installer and its executable payload need
their respective release-signing/notarization workflows. A standalone executable
cannot carry a stapled notarization ticket; offline release qualification must
choose a supported delivery carrier rather than claim a bare file is stapled.

### Portable ad-hoc measurement verification

`libs/image/signature.zig` verifies the bounded SHA-256 ad-hoc profile used by
the current compiler finalizer. It validates SuperBlob ranges and non-overlap,
CodeDirectory versions and flags, code coverage through the signature offset,
every code-page hash, and each present embedded special-slot hash. Missing
external slots must have zero hashes. Unknown algorithms, unsupported flags,
nonempty CMS signatures and unsupported descriptor layouts fail explicitly.
Signature storage has its own 256 MiB bound; it does not reuse the 1 MiB native
header limit. File coverage is streamed.

This verifier establishes that the image matches its ad-hoc measurements. It
does not authenticate a publisher, evaluate CMS chains or requirements policy,
grant entitlements, establish Gatekeeper acceptance or replace real-OS code-load
qualification. Embedded special blobs are measured; their policy interpretation
belongs to the operating system.

The pinned `rcodesign` 0.29.0 signer produces signatures accepted by native
`codesign`, but its general `verify` command rejects these valid ad-hoc images
while parsing the empty CMS wrapper. The current finalizer therefore uses the
portable measurement verifier after signing. Evidence preserves the upstream
failure and native verification of the same bytes. Release profiles requiring
publisher authentication must supply a verifier for that stronger profile.

`N2-IMAGE-03` covers page/content tampering, special-slot mutation, malformed
coverage/page counts, unsupported directories, parser allocation failures and
agreement with native verification of an actual Linux-signed Mach-O.
`N2-IMAGE-04` covers full native-prefix measurements, mask bounds and overlap,
format/CPU separation, code/data/header tampering, and measurement preservation
through actual native assembly and signing.

`N2-IMAGE-02` covers descriptor validation, parser allocation failures and fuzz
corpus, multi-format assembly with large payloads, unchanged executable sections,
source capture, overlap-safe signature movement and tamper rejection. Tests
record which target actually executed. Cross-host evidence records the Linux
assembler/signer bytes and the exact resulting setup executed on each target.

## References

- [Microsoft PE format](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format)
- [Apple Silicon code-signing requirement](https://support.apple.com/en-in/guide/security/secebb113be1/web)
- [Apple Notary API](https://developer.apple.com/documentation/notaryapi)
- [Custom notarization workflows](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Apple codesign implementation](https://github.com/indygreg/apple-platform-rs)
- [Apple code-signing blob layouts](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/cs_blobs.h)
- [Apple CodeDirectory definitions](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/codedirectory.h)
- [Authenticode implementation](https://github.com/mtrojnar/osslsigncode)
