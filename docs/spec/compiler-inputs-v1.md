# Compiler inputs and stage cache v1

- **Status:** Normative target under [ADR-0023](../adr/0023-standard-content-and-component-contracts.md).
- **Owners:** `libs/compiler/lock.zig`, `libs/compiler/cache.zig`, `libs/program/profile.zig`.
- **Acceptance:** N2-COMPILER-01 and N2-PROFILE-01 in [N2 acceptance](../acceptance-plan-v0.2.md).

## Locked inputs

A lock records exact dependency identities before common compilation. Its schema
is 1. Each input has a unique bounded identifier, kind (`runtime`, `runtime_metadata`, `library`,
`content`, `tool`), exact version, acquisition origin, lowercase SHA-256, byte
length, optional target and dependency identifiers. Runtime entries require a
target. Dependencies must exist, must not repeat and must form an acyclic graph.

Versions identify fixed publications; the lock does not resolve ranges. A locked
build does not replace a missing input with another version. Origins explain
acquisition, not authority. A digest verifies byte identity; publisher authority
belongs to the selected trust contract. File and network reads must verify the
declared length and digest before publishing a locked input as available.

The decoder rejects unknown fields and schemas. Native and wire validation share
the same item, string and byte limits. Normalization sorts inputs and dependency
sets by identifier. Source-language binding order is a separate ordered value and
must not be normalized by this dependency-set rule.

## Runtime profile

A profile declares its identifier, target, program schema, runtime ABI, Component
profile, content profile and provided primitive versions. Profile schema 1 targets
program schema 2, runtime ABI 2, Component profile 1 and content profile 1. Targets
are `x86_64-windows`, `aarch64-macos` and `x86_64-linux`.

Primitive requirements use a unique identifier and an exact positive version.
Binding rejects a different target, missing primitive or different primitive
version. Declaring a primitive does not grant an instance permission to use it.
Actual capability availability and authority must also be checked by the host.

The runtime template's digest belongs to its locked input. Profile metadata must
be bound to that input before it is trusted to describe the executable. A decoded
profile alone does not establish that a runtime implements it. The
[runtime publication package](runtime-package-v2.md) separately declares a fixed
native CPU/ABI profile and binds it to the complete template bytes. A runtime lock
depends on a separately locked `runtime_metadata` input whose publication version,
template length, SHA-256 and target must agree with that runtime. The compiler
reads this metadata without executing the target. Publisher authorization remains
a separate trust contract.

## Stage identity and local cache

A cache key includes compiler version, stage, target, normalized semantic-model
digest, runtime-profile digest, backend-option digest and normalized locked input
identities. Source maps and acquisition locations do not change the semantic key.
Stages are validation, binding, encoding and image assembly. Signing and author
program evaluation are not cached by this contract.

The caller supplies a private cache directory. Each record is bounded schema-1
JSON naming a byte length and SHA-256 blob. Readers reject symbolic record/blob
paths, malformed records, missing bytes, length mismatch and digest mismatch.
Damaged records are cache misses. Other IO failures remain visible failures.
Every consumer still applies the owning stage's output validation to a cache hit.

Writers acquire a nonblocking per-key file lock and use exclusive temporary files.
Blob bytes are hashed again while copying, synchronized, then atomically published.
Only afterward is the record atomically published. Interruption can leave an
unreferenced blob but cannot expose a partial record as a valid hit. Another value
under an already valid key is a determinism error, not permission to overwrite it.
Busy writers and cancellation have explicit errors. Cancellation is checked at
bounded copy chunks and before publication; source bytes changing during copying
cause a digest failure.

Cache retention and quota-based garbage collection are later work. Cache misses
must remain correct without relying on retention. No engine-serialized Wasm code
is accepted through this cache contract.

## Validation

Vectors cover equivalent input orders and acquisition locations, changed model,
target and locked bytes, dependency cycles, missing references, malformed hashes,
wrong runtime targets, unavailable primitive versions, corrupted records/blobs,
concurrent publication, cancellation and symbolic cache paths.
