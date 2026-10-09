# Capability library v2

- **Status:** Normative for Component profile 1; product and platform qualification is recorded separately.
- **Decision:** [ADR-0023](../adr/0023-standard-content-and-component-contracts.md), amended for the Component implementation language by [ADR-0026](../adr/0026-pinned-rust-component-wasm.md).

## Contract and identities

A library is a standard WebAssembly Component. WIT defines its interfaces and
value types; the Component Model Canonical ABI defines guest calls. Niobium MUST
use community bindgen and runtime implementations for that ABI. Its native C API
bindings and host value adapters MUST NOT implement a separate guest memory ABI.

A compiled call selects a locked library identity, an exported WIT interface ID
and a function name. An empty interface selects a world-level function. WIT
package/interface versions, library implementation digests, runtime profile
versions and persisted state versions are independent. Changing an implementation
does not establish state compatibility. The compiler MUST inspect the actual
locked Component bytes and validate argument types, projections, dependency
edges, migration functions and result roles before assembly. Input declarations retain the complete resolved WIT domain,
including unused-input validation at runtime; a default value is not an enum or
variant type declaration.

The official files library and product libraries use the same rules. Library
origin grants no authority. The runtime MUST NOT search for replacement modules,
load ambient modules, upgrade a dependency, or reinterpret an unavailable
primitive as success.

## Supported values and imports

Profile 1 supports synchronous bool, integer, float, char, string, list, tuple,
record, variant, enum, option, result and flags values. Integer widths and signedness
are exact. Host record/enum/flags matching uses names; tuple order is significant.
Non-finite floats and invalid Unicode scalars are rejected by the durable host
value model. Byte sequences are the host representation of WIT `list<u8>`.

Resources are supported inside an engine session, including constructors and
methods. Owned or borrowed resource handles MUST NOT cross the durable worker
protocol, compiled graph edges, migration state or journal boundary. A library
that needs durable identity uses typed values and explicit host validation.
Async, futures, streams and unsupported Component types are rejected at the call
boundary for this profile.

Imports have two distinct meanings:

1. A nonempty instance containing only resource-free value type declarations
   carries no callable authority. It may be resolved structurally without a host
   primitive declaration. The compiler and worker MUST apply the same bounded
   type-only predicate to every member and nested type.
2. Functions and resources require an explicit host contract and runtime
   implementation. An import name alone is insufficient authorization.

Type-only validation rejects empty instances, mixed function/type instances,
resource members, nested own/borrow resource types, unsupported types, invalid
names and excessive depth or node counts. The `wasi:` namespace is rejected even
when an interface contains no functions. Accepting a new resource-free type
package does not require a native runtime release. Function import support requires an explicitly newer Component profile.

Profile 1 products MUST reject callable imports at both compilation and runtime.
The production worker accepts type-only imports and invokes libraries
with prebound typed inputs and observations. It does not implement callable host
imports. The engine qualification fixture separately registers an explicit
`fact` callback to test host-call accounting and standard ABI behavior; that
fixture does not establish production primitive availability.

## Engine and isolation profile

The qualified implementation uses Wasmtime 49.0.2's official Component C API,
Pulley, and standard `wit-bindgen`. Cranelift prepares Pulley interpreter bytecode
from checked standard Component Wasm; it does not emit native guest machine code
for this profile. Replacement of this implementation follows
[ADR-0026](../adr/0026-pinned-rust-component-wasm.md).
Product-supplied serialized engine artifacts MUST NOT be accepted. WASI,
guest threads, async components, native guest JIT and automatic module
loading are disabled.

Before compilation, the upstream Wasm parser rejects every nested core or
Component start section and enforces structure bounds. This scan supplements
full Wasmtime validation. The type budget counts every core subtype inside a
recursive group and recursively counts Component/core-module type declarations,
including aliases, imports and exports inside type scopes. Nesting bounds cover
binary module/component nesting and nested type scopes. Instantiation and explicit
calls share the session's
fuel and memory limits. A failed Canonical ABI call invalidates that evaluation;
callers MUST discard the instance rather than retry it.

Every production inspection or invocation runs in a disposable child process.
The journal-owning parent MUST enforce a deadline, cancellation, bounded request
and response streams, and abnormal-termination handling. The child MUST verify
the declared source length and digest from the actual bytes read before loading.
A file source has an exact length; an image range has an explicit offset and
length. The worker MUST NOT discover libraries through search paths.

Current defaults are owned by `contracts.Limits` and the process client:

| Boundary | Profile 1 default |
|---|---:|
| Component bytes | 4 MiB |
| Nested modules / types / depth | 64 / 4096 / 32 |
| Guest memories / aggregate linear memory | 1 / 32 MiB |
| Tables / elements per table / Wasm stack | 64 / 4096 / 256 KiB |
| Explicit execution fuel | 1,000,000 per session |
| Rust allocation allowance | 128 MiB per disposable worker |
| Encoded request / response | 1 MiB / 64 KiB |
| Worker wall-clock deadline | 30 seconds |

The Rust allocator quota covers engine allocations, including Canonical ABI
lifting. Store limits separately constrain linear memory and tables. The quota
is not a whole-process RSS limit. Native request parsing, type reflection and
value conversion have independent bounded-input/node limits. Allocator exhaustion
may abort the worker, and MUST NOT abort the journal parent. The parent treats the
allocation marker as a budget error; all other abnormal exits still fail closed.
Encoded output limits apply after serialization as well as to decoded content.

## Desired resources and state

[The shared WIT package](../../api/wit/runtime/proposal.wit) defines content
references, generated entries, access policies and desired containers. A desired
container names an authorized logical root, grant and relative prefix. Its source
is either a fixed content reference or generated entries. Generated entries
carry file bytes, directories or explicit symbolic links. They do not carry a
self-certified content identity.

The host validates paths, names, ownership, access ceilings and resource budgets;
freezes accepted content into the canonical
[content container](content-container.md); and mints its durable identity.
File and directory desired access policies are required and currently apply
uniformly within each container. Source mode is not authorization. Mixed access
requires explicit content partitioning; equal controlled directory policies may
coalesce. A grant is a ceiling,
not a default desired policy. See [access policy v1](access-policy.md).

The shared string-state `plan` is a convenience type. A library may define a plan
record with its own supported private-state type while reusing the common desired
container types. The compiler validates the structural plan shape and the
corresponding migration result type. Product selection, layout, component
families and upgrade policy remain library/author responsibilities.

A guest proposal is never an imperative filesystem write. The host collects and
validates all proposals before durable effects, and recovery replays frozen host
plans without rerunning the guest or author program. Migration identity,
source/target state versions and implementation digest are explicit compiled
inputs; an absent or incompatible path is a refusal.

## Errors and conformance

A WIT `result<..., error>` is a library result. Traps, denied imports, type errors,
budget exhaustion, malformed IPC and process failures are separate host failures.
They MUST NOT be converted into a successful empty resource set. No evaluation
failure publishes partial guest output.

`component-test` exercises independent C and Rust generated bindings, typed values,
resources, fuel, memory, output expansion, automatic initialization, unauthorized
imports, empty WASI imports and process isolation. Its production IPC cases use
the shared client and both the official files and independent reference library.
Pure tests cover malformed type-only imports. Evidence is stored separately under
`.evidence/component/` and `.evidence/component-ipc/`; these suites do not establish
complete installation, recovery, signing or platform support.
