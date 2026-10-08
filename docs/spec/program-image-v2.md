# Compiled product v2

- **Status:** Normative v2 contract; qualification is recorded in the N2 acceptance ledger.
- **Decision:** [ADR-0023](../adr/0023-standard-content-and-component-contracts.md).
- **Owners:** `libs/program/model.zig`, `libs/program/value.zig`, `libs/program/wit.zig`.
- **Wire schema:** [compiled-program-v2](../../api/schema/compiled-program-v2.schema.json).

## Purpose and boundaries

The compiled product fixes a typed graph of standard Component function calls,
runtime inputs, observations, content identities and authority. Authors construct
this model through a build-time SDK. Its serialized form is compiler output.
Functions, conditions, loops and project composition remain in the author language
or in a fixed capability library; the graph has no expression evaluator.

This contract replaces the v1 product model for v2 runtimes. It does not change
retained v1 evidence or promise automatic conversion of old installed state.
The [native image contract](setup-image-v2.md) owns executable packaging. The
[content contract](content-container-v1.md) owns portable logical trees.

## Identities and objects

| Object | Identity and meaning |
| --- | --- |
| Product | Stable `id`, monotonic `release_sequence`, explicit `model_version` |
| Input | Stable ID, typed default and compiler-resolved complete WIT type |
| Library | Stable local ID, payload member, exact standard Component byte digest and length |
| Container | Stable local ID, payload member and canonical `ContainerRef` |
| Root | Product-defined authority anchor bound to a user-scope native directory at runtime |
| Grant | Named root and primitive authority, path prefix, entry/byte ceilings and access ceilings |
| Observation | Named read-only host function, fixed primitive version and literal arguments |
| Call | Stable capability instance ID, fixed library/interface/function, typed bindings and role |
| Migration | Named direct state conversion with a fixed converter and implementation digest |

Each collection has its own ID namespace. A library ID and an author input ID may
coincide. Source-map keys qualify that namespace. Payload member names must be
unique across libraries and containers. The compiler input lock is a separate
namespace: every included library/container resolves one exact locked source.

Raw source bytes, normalized container bytes, generated container bytes, the
runtime template, compiled product and final setup have distinct identities.
A source tar's SHA-256 is not assumed to equal its canonical tree SHA-256.
`ContainerRef` contains `format`, `sha256` and `bytes`; it contains no open handle,
host path, process address, retrieval policy or source provenance.

## Fixed compatibility and authority

`schema` and `runtime_abi` are 2. `target` selects one explicit native target.
The embedded profile declares exact program, Component, content and primitive
versions. The compiler compares it with independently locked runtime-package
metadata, rather than accepting an author's unsupported profile claim.

The current profile covers `x86_64-linux`, `x86_64-windows` and `aarch64-macos`,
user scope and CLI operation. A target name alone does not establish real-OS
qualification. Unknown primitive versions and machine scope fail explicitly.

A library's `requires` set declares exact primitive requirements. Component
profile 1 permits only pure type-only imports for ordinary reusable WIT data
types. Read-only host functions are evaluated as declared observations and their
typed results become call arguments. Callable imports, including a function with
a matching declared primitive contract, are rejected during compilation. A
future profile may define host call linkage and its authority protocol; profile
1 must not accept a library that its worker cannot instantiate. Ambient WASI and
unresolved imports are rejected.

Calls receive only their declared grants. A grant's `file_access` and
`directory_access` are ceilings. Desired policies must be explicit in successful
proposals; ceilings never become implicit permissions. Portable access validity,
including the readable-owner floor, belongs to the access contract.

Read-only preflight checks content identities, logical trees, conflicts and
aggregate grant budgets before any new CAS object is published. Materialized
prefix directories count toward the entry ceiling. Synthesized directories
strictly above a grant's prefix use the fixed private host directory policy;
the guest cannot assign their access rights. Frozen inventories retain that
policy, and captured content is checked again before generation preparation.
Logical names compare as exact UTF-8 bytes. Target adapters reject unsupported
native names; exclusive staging detects actual filesystem aliases before commit.

When roots exist, `state_root` must identify their transaction coordinator.
Binding roots to native paths does not create authority outside these roots.
The coordinator records one durable decision for all participating roots;
cross-root simultaneous visibility is not promised.

## Typed graph and ordering

`Binding` supports literals, author inputs, observation results, prior node
results and the owning call's `previous_state`. A projection selects record
fields by name. `record`, `list`, `tuple` and `some` construct standard aggregate
values from bindings. They add no arithmetic, branching, string interpolation or
dynamic function selection. An absent option is a literal `option: null`.

Function parameter order, list order and tuple order are significant. Records,
flags and ID-keyed collections normalize by name. Referenced results add graph
edges; `after` adds explicit sequencing. The compiler rejects missing references
and cycles, then chooses lexicographic call IDs among ready nodes. Nested
aggregate references participate in exactly the same dependency analysis.

Bindings are checked against types reflected by the upstream Component engine.
Integer widths remain exact; `u64` never passes through a floating-point JSON
representation. Strings are UTF-8, floating-point values must be finite and
characters must be Unicode scalars. Resources are session-local and cannot be
stored as graph values, prior state or durable proposals.

The common semantic budget is depth 32 and 4,096 nodes, with a 1 MiB encoded
product limit. Native pointer cycles are rejected before serialization. JSON
wrapper depth is separately bounded at 144; it does not increase semantic depth.
Allocation failures and malformed inputs return errors.

Author inputs leave `resolved_type` null. The compiler gathers the complete WIT
type at every nested input use, validates the default and requires all uses to
have compatible full domains. It does not intersect or narrow enum domains to
fit the chosen default. Unused inputs infer only determinate scalar, byte-list,
record, tuple, nonempty homogeneous list and present-option types. An unused
empty generic list, absent option, enum, flags, variant or result is ambiguous
and fails compilation; a future explicit type-declaration API may resolve it.
Author-supplied resolved types are rejected. Every emitted input has a concrete
type, checked against overrides and retained values before resource evaluation.
The type descriptor reuses the standard WIT type model rather than a separate
input-validation language.

## Successful plan values

A call declares `result_role: value` or `plan`. A value call exposes its exact
standard WIT result, including options or results. A plan call may return the
common plan directly or `result<plan, E>`; an error arm aborts evaluation.
Its successful plan contains `containers: list<container-proposal>` and
`state: option<T>`. Additional plan fields may feed downstream bindings.

Each container proposal contains `root`, `grant`, `prefix`, `container`,
`file-access` and `directory-access`. `container` is the standard WIT variant
`reference(container-ref) | generated(list<entry>)`. The reference format is
`posix-pax-v1`, a 32-byte SHA-256 list and an unsigned byte length. A generated
entry contains a logical `path`, ordinary `mode: u16`, and the variant
`file(list<u8>) | directory | symlink(string)`.

The host validates and canonicalizes generated entries into a private content
file. It computes the resulting identity, replaces the generated arm with the
reference arm in the stored node result, and only then permits downstream calls
to observe that result. The WIT type stays unchanged. Guests cannot assign a
generated identity, select a host source path or cause a digest search outside
the declared and already frozen content set.

The current evaluation profile bounds each generated canonical container at
4 MiB and all retained generated containers at 64 MiB. General content/image
streaming limits are independent. Guest evaluation proposes resources; the host
checks ownership, grants, conflicts and limits before freezing a durable plan.
Recovery consumes that plan without reevaluating the graph or guest.

## State and explicit migration

State belongs to `Call.id`, not to a library package as a whole. The persisted
owner also fixes library ID, interface, function and state version; implementation
digest is recorded separately. Two calls into one library do not share implicit
state. A same-selector implementation update may retain a state version. A
version change requires a declared applicable converter with the locked digest.

`previous_state` is the owning call's `option<T>` after migration. A converter
accepts the previous typed state and returns the destination type, optionally
wrapped in a standard result. Unknown versions, missing edges and digest/type
mismatches fail before mutation. Cross-selector ownership bridges are outside
this direct-edge profile and must not be inferred from a version number alone.
Product `upgrades` independently authorizes direct model-version transitions.

## Validation and evidence

`N2-MODEL-01` covers normalized identity and ordered semantics. `N2-MODEL-02`
covers references, authority, explicit migrations and allocation failure.
`N2-MODEL-03` covers aggregate budgets, cyclic native values and nested graph
edges. `N2-TYPES-02` covers durable WIT type compatibility. Compiler and runtime
scenario evidence must additionally demonstrate actual Component execution and
frozen recovery; schema validation alone cannot establish those results.
