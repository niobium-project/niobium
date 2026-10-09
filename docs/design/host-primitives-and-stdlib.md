# Host primitives and standard libraries

- **Kind:** Layering and extension design under [ADR-0023](../adr/0023-standard-content-and-component-contracts.md).
- **Owners:** Runtime kernel, primitive maintainers and independent library publishers.
- **Current boundary:** Content trees, user-scope generation deployment, access receipts,
  machine facts and explicit maintenance/migration are implemented. Other platform
  integrations retain their old owners until their new contracts are qualified.

## Responsibility boundary

| Layer | Responsibility | Extension boundary |
|---|---|---|
| Runtime kernel | Identity, grants, budgets, conflict checks, plan freezing, commit and recovery | Mechanisms common to every product |
| Host primitives | Bounded observations and machine operations with native adapters | Versioned authority, preconditions, receipts and recovery |
| Capability libraries / stdlib | Compose mechanisms into capabilities and product models | Public WIT contracts; fixed implementations |
| Author libraries / presets | Component families, workloads, layout, coexistence and distribution choices | Build-time SDK composition |

A library declaration requests a compatible primitive; a signed/authorized product
binding grants scope. Neither a WIT import nor a digest grants authority by itself.
The current Component profile supplies observations as typed values and accepts
declarative plans. Callable imports require a future qualified profile.

## Four primitive families

| Family | Objects and operations | Current slice | Further operations |
|---|---|---|---|
| Content | Immutable container, tree, member, source and derivation; inspect, select, remap, merge, generate, freeze | Canonical pax trees, build-time transforms, fixed references and bounded generated entries | Additional transport adapters, streaming guest content access and derivation tooling |
| Machine state | Typed observation with scope, provenance and freshness; inspect and compare | `machine.facts@1` reports OS and runtime/process architecture | Filesystem capabilities, prerequisites, integrations, running processes and hardware observations |
| Authority and ownership | Root, scoped grant, resource identity, access intent and native receipt; authorize, claim, verify, release | Exclusive product roots, per-call grants, private scaffolding, access application/restoration | Shared-object coordination and machine-scope broker contracts |
| Execution and maintenance | Frozen plan, generation, decision, installed state and migration; prepare, commit, recover, repair, remove | User-scope generations, multi-root coordinator, explicit state conversion and guest-free recovery | Services, application activation, restart continuation and embedded maintenance |

A missing prerequisite is an observation. Product libraries decide whether to
continue, disable a component, request another installation or fail. Detecting an
independent shared prerequisite never grants ownership of it or authorizes its
installation/removal.

`machine.facts.architecture` means the running runtime's architecture. An x64
runtime under OS emulation reports x64; this is not physical CPU detection.
More detailed machine facts need explicit contracts and provenance.

## Content and access

[Content container v1](../spec/content-container.md) owns logical naming,
metadata and canonical pax. Target name restrictions belong to native deployment:
Windows reserved names cannot become a global Linux/macOS naming policy.
Native exclusive creation detects filesystem aliases before commit. Symbolic link
text remains exact; native traversal and target-kind requirements are checked
before staging. Windows creation privilege is a separate runtime observation.

[Access policy v1](../spec/access-policy.md) defines the portable discretionary
subset. POSIX modes and Windows DACLs are separate representations. The host
verifies the requested policy and preserves native identity/metadata for recovery;
it refuses unsupported ACLs, filesystems or rules.

Archive mode never becomes authority automatically. A current desired container
has uniform file and directory policies. Authors can partition executable and
data content into distinct references with explicit policies. More granular
per-entry intent requires a bounded, versioned proposal and conformance vectors.

Strict ancestors above a granted prefix are private host scaffolding. Guest policy
applies only at or below its grant. Scaffolding is counted in resource budgets and
persisted with the actual private policy; it cannot widen rights above a grant.

## Lifecycle and durable identity

The [lifecycle specification](../spec/runtime-lifecycle.md) owns the detailed
state machine. The host checks grants and resource budgets before publishing
content into durable storage, then validates the captured inventory again. A
frozen plan contains stable identities, relative paths, hashes and versions.
Process handles and guest resources never enter it.

Every plan-producing call retains its owner/selector/version record even when its
private state is absent. Version changes require applicable conversion rules.
The current converter ABI consumes a value; changing a state version from absent
private state is an explicit unsupported transition, not an inferred conversion.

Each root prepares a complete generation. One coordinator decision determines
whether recovery retains OLD or completes NEW across all roots. There is no
simultaneous cross-root visibility guarantee. Recovery uses durable plans and
content, without guest or author execution. Repair and uninstall preserve changed
or unrecorded user data and refuse foreign publication pointers.

A new primitive must define observation, authority, ownership, idempotence,
verification, interruption, restoration and recovery. Operations without complete
rollback must declare their actual commit/reconciliation boundary. Removing a
library from a new product does not remove the need to recover an old frozen plan.

## Module ownership and platform matrix

| Module or capability | Owner and dependency direction | Qualification rule |
|---|---|---|
| `stdlib.files` | Public WIT and content references; no native module import | Same contract tests as independent product libraries |
| Content transport | Acquisition/trust mechanisms beneath source/distribution libraries | Exact bytes, bounded IO, authorization and offline failure cases |
| Channels, repositories, updates | Distribution libraries and presets | Product policy plus retained cryptographic mechanisms |
| Environment, shortcuts, services | New host primitive contracts and platform adapters | Ownership, drift and restoration for each OS/scope |
| UI and bootstrap | Typed inputs/progress or an explicit activation protocol | No implicit mutation authority; shared renderer boundary remains |
| SDK/workload/coexistence | Author/product libraries | Different policies through the same kernel and resource contracts |

The implemented runtime targets are macOS arm64, Windows x64 and Linux x64 in user
scope. This is an implementation matrix; actual execution, filesystem, emulation
and identity contexts are recorded separately in acceptance. Machine scope,
additional architectures, publisher trust and unsupported filesystem/ACL features
remain unqualified. No cell inherits a PASS from another OS or from compilation.

To add a primitive, first specify the interface, capability/profile version,
unsupported outcomes and failure vectors. Then implement the native adapter and
recovery path, qualify real effects on each claimed target, and publish a runtime
profile containing that version. Libraries and presets can evolve independently
once those contracts are fixed. [Product journeys](product-journeys.md) and
[roadmap v0.3](../roadmap.md) provide the parallel work packages.
