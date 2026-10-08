# Authoring C ABI v2

- **Status:** Normative for the typed authoring interface.
- **Decision:** [ADR-0023](../adr/0023-standard-content-and-component-contracts.md).
- **Header:** [compiler_v2.h](../../api/c/compiler_v2.h).

## Scope and version negotiation

The authoring ABI constructs a typed product model at build time through the
shared native `compiler.author.Builder`. It is independent of the runtime
embedding ABI, the legacy authoring ABI and the Wasm Canonical ABI. Version 2
symbols use `nbc2_`; creation MUST reject an unsupported ABI version and clear the
output builder pointer on failure. The retained `nbc_` interface keeps its own
header and implementation.

Authors provide typed C descriptors, not serialized expressions or JSON source.
Emission produces normalized machine IR for the common compiler backend. Every
frontend MUST use the same semantic validation and normalization. Emission does
not bypass later checks against locked runtime, Component and content bytes.

## Native static linkage

The published static archive includes Zig's compiler runtime support. GNU Windows
consumers MUST also link the system `ntdll` import library (`-lntdll`) after the
author archive. SDK packages and language bindings MUST carry this link requirement.
Zig's C linker supplies that platform import library automatically; external
C/CGO linkers need the explicit dependency.

## Ownership and memory

A builder is owned by one thread. Destroy it exactly once after all operations.
Input views, spans and construction objects are copied by successful constructor
operations; callers may release or mutate their source buffers afterward. Empty
spans may use a null pointer. Nonempty spans require a valid pointer for the call.
Pointer validity and avoiding use after destroy are C caller responsibilities.

`nbc2_object` identifies an immutable Value or Binding owned by one builder. The
implementation checks owner, kind and index before reading it. Cross-builder and
wrong-kind handles MUST fail. Objects need no individual free and expire with
their builder. A zero object means absent optional payload; it never means an
arbitrary valid object. No process pointer is serialized into the product model.

`nbc2_emit` returns a separate allocation. It remains valid after the builder is
destroyed and MUST be released using `nbc2_buffer_free`. Free clears the descriptor;
freeing that cleared descriptor again is harmless. Last-error text is borrowed
static storage, not an owned buffer, and the next successful operation clears it.

## Descriptor families

The header owns exact field layouts, enum values and exported signatures. These
are C layouts with explicitly sized tags and numbers, pointer/length spans and
opaque ownership. They MUST NOT expose Zig slices, allocators or error unions.
Descriptors MUST be zero-initialized. Unused fields are ignored.

| Descriptor | Meaning |
|---|---|
| Value | Exact-width scalar, text/bytes, list, tuple, named record, variant, enum, option, result or flags |
| Binding | Literal Value, input reference, prior-call projection, observation projection, previous state, or typed record/list/tuple/option assembly |
| Profile | Explicit runtime profile ID, target and primitive versions |
| Library | Identity, package member, lowercase hex SHA-256, size and primitive requirements |
| Container | Identity, package member, 32-byte binary SHA-256 and canonical size |
| Root / grant | Scope, primitive requirement, relative ownership prefix, resource budgets and access ceiling |
| Observation | Primitive/function identity, typed values and optional grant |
| Call | Fixed library export, typed bindings, ordering edges, grants, state version and migrations |
| Migration / upgrade | Explicit identity and version transition; library state also fixes the converter implementation |

Boolean values use flags 0 or 1; result uses 1 for success and 0 for error. The
payload object is optional for option, variant and result. Enum/variant/flags
names retain their WIT meaning. Positive access rights use read=1, write=2 and
execute=4; directory execute is invalid in access policy v1. No native mode bits
or ACL bytes are accepted as deployment access intent.

All views, spans, aggregate depths and object counts are bounded. Narrowing an
untrusted integer MUST reject overflow. Unknown tags, invalid Unicode,
non-finite floats, malformed handles and unsupported targets fail explicitly.
References may be forward references during construction; normalization and
compiler binding MUST reject unresolved references, cycles and incompatible
contracts before a setup image can be emitted.

## Runtime input types

Authors supply input identity and a typed default Value. The compiler owns the
compiled `resolved_type`; an author-provided value for that field is rejected.
The backend derives a complete WIT type from every use site and requires those
uses to agree. It does not intersect enum domains or infer a singleton enum from
the default case. Defaults are validated against the complete resolved type.

An unused default can determine bool, exact numeric/char/text/byte types,
records/tuples of determinate values, a homogeneous nonempty list, or `some(T)`
when T is determinate. Empty generic lists, `none`, enums, flags, variants and
results do not determine their complete type and require a typed use site.
An ambiguous unused input fails with a diagnostic; it is not persisted as an
unconstrained value. A future explicit-Type SDK extension must reuse standard WIT
types and must still match every use site.

Compiled inputs require a resolved, bounded, resource-free type. Runtime overrides
and retained input values are checked against the applicable declaration before
machine effects, including inputs that no selected call happens to consume.
Generic Value-shape validation alone is insufficient.

## Diagnostic source maps

`nbc2_location` records or replaces a qualified object location such as
`call:configure` or `library:files`. File, line and column are copied; positions
are one-based. Qualified keys distinguish product, library, container, call,
observation, lock input, root, grant and author-input namespaces. Unknown kinds,
invalid IDs, empty/oversized paths and zero positions are rejected.

`nbc2_emit_source_map` returns an independently owned schema-1 sidecar containing
`locations`. It uses the same buffer release function as model emission. Source
maps have a separate bounded ownership budget and MUST NOT enter normalized
semantic bytes, runtime products or compiler cache identity. The compiler matches
its diagnostic object kind and ID against the sidecar; missing positions remain
explicitly absent rather than invented.

## Errors and compatibility

| Status | Meaning |
|---|---|
| `NBC2_OK` | Operation completed |
| `NBC2_INVALID_ARGUMENT` | ABI, pointer/span shape, tag, integer bound or handle is invalid |
| `NBC2_INVALID_PROGRAM` | Shared model, profile, value, authority or construction limit rejected the input |
| `NBC2_OUT_OF_MEMORY` | Allocation failed |

The diagnostic name returned by `nbc2_last_error` explains a failed builder
operation. A status code is stable at the C boundary; diagnostic names identify
the owning semantic error. Expected input errors MUST NOT panic across the ABI.
Output objects/buffers MUST be cleared before a failing operation can expose them.

Public descriptor or semantic changes require an explicit version decision and
updated C, native and hosted consumer vectors. The ABI does not infer old state
compatibility from a reused product ID. Compiled-product and migration contracts
own those decisions.

## Verification

`zig build author-v2-test --cache-poison=disallowed` compiles an independent C
consumer against the actual header, runs ABI ownership/type tests and evaluates
native Zig, C and Starlark programs. The three reference authors exercise function
and module composition, typed record bindings, machine observation, grants and a
fixed real Component identity, then compare normalized program bytes. Evidence
under `.evidence/author-v2/` records source and executable identities. This suite
proves authoring equivalence; product execution uses the separate end-to-end lane.
