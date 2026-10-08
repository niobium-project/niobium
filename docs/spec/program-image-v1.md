# Compiled program and setup image v1

- **Status:** Normative target; implementation evidence is in [N2 acceptance](../acceptance-plan-v0.2.md).
- **Decision:** [ADR-0022](../adr/0022-installer-dsl-and-aot-toolchain.md).
- **Machine contract:** [compiled-program-v1.schema.json](../../api/schema/compiled-program-v1.schema.json).

## Program model

An unbound runtime template starts its reserved section with `NIORT001`, followed
by little-endian u32 runtime ABI `1` and section capacity. The rest is zero.
Assembly checks this descriptor before filling the section; an already bound
setup is not a runtime template. This descriptor is compatibility metadata,
not publisher authentication.

The program is immutable product output produced through the authoring SDK. JSON
is its machine serialization for this version. It carries typed objects and
bindings; runtime does not interpret author-language expressions.

| Field | Type | Meaning |
|---|---|---|
| `schema` | integer, exactly 1 | Program format version |
| `runtime_abi` | integer, exactly 1 | Required host contract |
| `product_id` | bounded identifier | Product identity |
| `release_sequence` | unsigned 64-bit integer | Product release ordering value |
| `model_version` | unsigned 32-bit integer | Product model version |
| `inputs` | Input array | Named runtime input defaults |
| `libraries` | Library array | Frozen capability implementations |
| `assets` | Asset array | Immutable bytes available to libraries |
| `resources` | Resource array | Product-owned relative output locations |
| `instances` | Instance array | Library invocations and scoped bindings |
| `upgrades` | Migration array | Product-declared model transitions |

| Object | Fields | Meaning |
|---|---|---|
| Input | `id`, `default` | Text supplied to a bound guest input handle |
| Library | `id`, `abi`, `sha256`, `wasm_hex` | ABI 1, digest and exact Wasm bytes |
| Asset | `id`, `sha256`, `data_hex` | Digest and exact payload bytes |
| Resource | `id`, `path` | Stable identity and normalized relative path |
| Instance | `id`, `library`, `inputs`, `assets`, `resources`, `state_version`, `migrations` | One library instance, ordered bindings and state contract |
| Migration | `id`, `from`, `to` | Identified forward transition between model or library-state versions |

IDs use bounded ASCII `[a-z0-9._-]`. Resource paths are normalized and relative.
The PoC restricts them to printable
ASCII, 1024 bytes and 62 components to avoid filesystem Unicode aliases and leave
room for the generation prefix. Installation-root paths may use Unicode. Absolute
paths, parent traversal and ambiguous components are rejected. The case-insensitive
`.niobium-generation` name and its descendants are reserved for host metadata.
Digest strings
identify decoded bytes with lowercase SHA-256. Malformed hex and mismatched
digests are errors. Library ABI is 1; an instance state version defaults to 1.

The model contains no global component, SDK, channel or installation-layout enum.
Those concepts can be composed in author libraries and represented by capability
instances. A product's policy cannot bypass runtime ownership or authority checks.

## Validation and normalization

`libs/program` owns `validate`, `normalize`, `encode` and `decode`. All boundaries
enforce the limits in `contracts.Limits`, reject unknown fields and invalid
versions, and check references before runtime mutation.

The serializer emits all fields. Decoder defaults are recorded in the schema;
library and instance arrays default to empty. An empty capability set is valid,
including a release that removes all previously selected capabilities.
Input defaults are valid UTF-8 text. Native authoring byte views with invalid UTF-8
are rejected before normalization or serialization; valid Unicode text is preserved.
JSON Schema lengths count characters. Native limits count UTF-8 bytes, and the
complete encoded program also has its own byte ceiling. Lowercase hex uses two
characters per decoded byte.

Collection IDs are unique
within their namespace. Resource output locations cannot have conflicting owners, case-insensitive aliases
or ancestor relationships. A capability can emit any subset of its resource grants.

Collections normalize by ID. An instance's `inputs`, `assets` and `resources`
lists retain author-declared order because guest handles index those lists.
Normalization never changes the meaning of an indexed binding.

The compiler and runtime apply the same program validation. Runtime also validates
library profile restrictions before guest execution. A valid digest identifies
bytes; it does not establish publisher authority or make guest behavior safe.

## Setup image

The initial carrier is a complete macOS arm64 executable with a reserved
`__DATA,__nbproduct` section of exactly 1 MiB. The compiler locates that section
through Mach-O metadata and fills it without relinking the runtime. The image
contains a versioned frame, normalized program, content digest, runtime-template
digest and zero padding. Actual frame constants and byte layout are owned by
`libs/program/image.zig` and its shared compiler/runtime tests.

The runtime reads its executable using Mach-O section offsets. It never assumes
the program is at EOF because signing can append data. Image parsing checks magic,
version, declared length, content digest, section capacity and zero padding.
Missing, duplicate, truncated or malformed sections fail before product execution.

The 1 MiB carrier is an explicit proof-of-concept limit, including embedded library
and asset bytes. Larger authenticated carriers and other executable formats need
a versioned backend contract. They must preserve the template input and executable code sections without
relinking. Only the output product section and signing metadata change.

Final ad-hoc signing follows embedding. The template digest and signed executable
digest have different meanings and must never be compared as if they were equal.
Release trust and publisher signatures require separate qualification.

## Runtime choices and acceptance

The CLI binds an explicit installation root and declared `--set name=value`
choices. Binding observes the same IDs as the program; unknown input names are
errors. Runtime OS and architecture come from the host, not a product claim.
Within the initial profile, a lower release sequence is refused. Reusing a
sequence with a different normalized program digest fails with
`ReleaseIdentityMismatch`. Changing only runtime input values is reconfiguration
and does not change program identity.

The program and bindings produce a deployment plan under
[runtime-lifecycle-v1](runtime-lifecycle-v1.md).

- `N2-AUTH-01`: native encode/decode/normalization vectors preserve binding order.
- `N2-SAFE-01`: invalid IDs, paths, references, duplicate owners and digests fail closed.
- `N2-IMAGE-01`: image extraction works after signing and rejects malformed frames.
- `N2-AOT-01`: independent products preserve one runtime-template identity.
