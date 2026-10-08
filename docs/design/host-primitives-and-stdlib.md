# Host primitives and standard libraries

- **Kind:** Architecture and interface design under [ADR-0022](../adr/0022-installer-dsl-and-aot-toolchain.md).
- **Audience:** Runtime, platform, capability and product-library maintainers.
- **Implementation boundary:** The PoC provides user-scope generation files and fixed facts. Other primitives and standard-library modules require their own implementation evidence.

## Responsibility boundary

The kernel owns identity, authority, resource collision checks, budgets and transaction integrity. A host primitive gives a checked mechanism a versioned effect and recovery contract. A capability library combines those mechanisms into a domain capability.

Standard libraries express common installation and distribution models. Presets select conventions such as component selection, SDK coexistence and update policy. Product libraries may choose different conventions while respecting the same host contracts.

| Layer | Inputs | Outputs | Prohibited dependency |
|---|---|---|---|
| Author library/preset | Product build options | Typed model and capability bindings | Runtime evaluation of author source |
| Capability library | Bound inputs, facts, assets and prior state | Desired resources and resulting state | Native platform modules or ambient OS authority |
| Kernel | Compiled program and observed state | Validated frozen transaction | Specific component/channel policy |
| Host primitive | Authorized frozen operation | Durable effect and receipt | New guest decisions during recovery |
| Platform backend | Primitive operation and explicit IO | Platform result or explicit unsupported error | Product selection policy |

The current profile validates printable-ASCII resource paths and file outputs, stages a generation and switches its active pointer. Installation roots may use Unicode. That deployment profile is not a requirement that every future primitive uses file generations.

## Primitive contract

Every new primitive defines identity/version, request and result types, permitted scope, ownership key, preconditions, limits and error categories. It also defines observable state, conflict detection, durable undo data and post-crash reconciliation.

A contract distinguishes observation from mutation. Observation returns a bounded snapshot with provenance and freshness requirements. Planning consumes the snapshot and proposes effects. Commit checks any preconditions that could have changed since observation.

The guest receives scoped handles. The host derives grants from the compiled binding, runtime profile and actual privilege context. An import or package declaration cannot enlarge those grants. Handles expire after their evaluation and never enter a persistent plan.

Persistent operations use resource identities and validated root-relative references. OS handles are reopened and checked during recovery. Link traversal and parent replacement must not redirect a write outside the owned root. Unsupported operations return a typed refusal before mutation.

## Resource lifecycle

A resource owner is the product instance plus a stable resource ID. Library implementation updates do not implicitly transfer ownership. Two proposed resources that collide on a physical location are rejected before either is written.

The host freezes contents, identities, preconditions, migration receipts and operations before staging. Each primitive defines prepare, apply, verify, rollback and recovery behavior where applicable. A resource may require a narrower supported lifecycle; the compiler rejects a requested lifecycle that the runtime cannot provide.

Uninstall reconciles ownership with current state. A product cannot delete unowned data because it shares a directory. A library cannot promise rollback for arbitrary external side effects; introducing such a primitive requires an explicit lifecycle decision and failure semantics.

Transaction compatibility includes primitives referenced by unfinished plans and installed resource receipts. A smaller runtime profile must refuse maintenance if it lacks required recovery or cleanup implementations. Removing a capability from the new product model does not remove this obligation.

## Primitive and library catalog

The table assigns design ownership. Only the first row is part of the executable PoC.

| Capability area | Host mechanism | Standard-library policy | Platform/scope design |
|---|---|---|---|
| Managed files | Bound assets, desired byte outputs, owned generation activation | Layout and deployment grouping | macOS arm64 user PoC; other combinations need qualification |
| Directories/archives | Bounded extraction, metadata and safe path operations | Artifact packaging and layout | Per-platform permissions and link semantics |
| Shortcuts/protocols/file associations | Typed registration, ownership receipts and restoration | Naming, associations and optionality | macOS/Windows/Linux, user/machine assessed separately |
| Services/autostart | Closed service-manager operations | Start policy and product integration | Explicit supported manager and scope; no arbitrary command import |
| Environment/PATH | Typed entry identity, read/compare/write and removal | Stable path selection and precedence | Preserve unrelated entries and user edits |
| Sources/cache | Authorized bounded byte acquisition and content storage | HTTP/offline selection, caching and mirrors | Network authority independently granted |
| Release trust/channels | Signature/hash and metadata verification | TUF profile, channels, promotion and release authorization | Trust requirements cannot be bypassed by guest declarations |
| Activation | Typed product activation protocol with timeout | Business compatibility and pending/retry policy | Separate process authority; no implicit deployment rollback promise |
| UI | Input/state contract and read-only progress | Screens, themes and workflow | Shared renderer per ADR-0008; CLI shares semantics |

Every platform/scope cell starts without an N2 support claim. The implementation owner must supply backend conformance, failure tests and real-OS evidence before changing its qualification status.

## Standard-library dependency design

`stdlib.files` depends on file primitives and the capability ABI. Artifact libraries may depend on files and extraction. Distribution libraries compose sources, trust and artifact identities. Product composition libraries bind capabilities and own component families, workloads and selection migration.

Presets depend on standard or product libraries. They never become dependencies of the kernel. A preset's version and evaluated output are fixed by the build; modifying a preset does not change an existing setup.

SDK coexistence is represented through stable resource identity and library state. Single-version and multi-version policies are separate author-library choices. Upgrade paths and migration mappings remain explicit product declarations.

## Introducing an operation

The primitive owner updates the owning contract, platform/scope matrix and negative tests before implementation. The runtime profile advertises the new versioned operation. The compiler checks the required grant and target before assembly.

A library can use a new primitive only with a compatible published runtime. Host bindings validate request shape and authorization again at execution. Privileged implementations require a closed helper operation and authenticated session; granting a generic execution import is not an extension mechanism.

Acceptance covers apply, interruption before and after each durable boundary, repeated recovery, conflicting ownership and unsupported targets. The [module transition table](../architecture/module-boundaries.md) records reuse of current modules. [The roadmap](../roadmap-v0.2.md) assigns parallel owners.
