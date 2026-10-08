# Roadmap v0.3: Standard core infrastructure

The implementation baseline is [ADR-0023](adr/0023-standard-content-and-component-contracts.md).
Its qualification gate does not change prior product evidence. The retained
[v0.2 roadmap](roadmap-v0.2.md) and its evidence keep their original scope.
[Acceptance v0.3](acceptance-plan-v0.3.md) records current qualification.

## Required delivery

The delivery includes standard content containers, WIT capability interfaces,
four primitive families, a portable access subset, a staged compiler and
cross-host native product assembly. Zig/C/Starlark share author semantics. Linux
x64 must assemble Windows x64, macOS arm64 and Linux x64 setups from precompiled
runtimes. The exact outputs must execute on their target OS before qualification.

| Package | Owner | Dependencies | Deliverable and acceptance |
|---|---|---|---|
| CORE-01 Contracts | Architecture maintainer | Approved design | Versioned contracts, schemas, WIT, source maps, glossary and positive/negative vectors |
| CORE-02 Component host | Wasm maintainer | CORE-01 | Pinned standard bindgen and Wasmtime/Pulley qualification; typed calls, resources, no ambient imports, bounded initialization/execution/allocation |
| CORE-03 Content | Content maintainer | CORE-01 | Bounded pax trees, transformations, identities and GNU/libarchive interoperability |
| CORE-04 Access | Platform maintainers | CORE-01 | Unified owner/everyone policy, exact native mapping, receipts, drift checks and effective access tests |
| CORE-05 Compiler | Compiler maintainer | CORE-01, CORE-02, CORE-03 | Shared authoring, WIT binding, exact dependency lock, validated cache, diagnostics and cancellation |
| CORE-06 Runtime | Lifecycle maintainer | CORE-02, CORE-03, CORE-04 | Typed observations, scoped grants, generated content, frozen plans, migration and guest-independent recovery |
| CORE-07 Native delivery | Image maintainer | CORE-01, CORE-05, CORE-06 | PE/ELF/Mach-O assemblers and host signing adapters; no target execution or runtime relink during assembly |
| CORE-08 Qualification | Test maintainer | Delivered slices | Real target lifecycle, permission and crash evidence; final artifact identities and regression gates |

Content, access and native image work can proceed independently after their
interfaces are fixed. Component qualification precedes replacement of the old
engine. Failure of that gate must name the missing guarantee; it does not authorize
a custom Canonical ABI or reduced safety coverage.

## Reference scenarios

1. A selected SDK composes several fixed artifacts into a content tree, with
   explicit conflicts, executable members, empty directories and symbolic links.
2. An independent library derives configuration from selected inputs, observed
   machine facts and installation location, returning a bounded new container.
3. A second library consumes a typed result without receiving undeclared write
   authority. Missing observations remain data for product policy.
4. Two releases migrate library state and resources together. Missing paths,
   changed migration identity and incompatible old formats refuse before mutation.
5. Update, repair and uninstall distinguish managed resources, user additions,
   permission drift and independent shared objects.
6. A Linux-hosted assembly produces all three native formats. Validation transfers
   those exact bytes to target systems; it never rebuilds substitute products.

## Gates and evidence

`zig build core-test` checks the shared content, access and compiler foundations.
The existing `aot-test` and `aot-e2e` retain their v1 profile until explicit new
lanes qualify replacement interfaces. Every implemented lane enters `verify`;
unsupported targets remain visible rather than passing through a skip silently.

Each handoff provides interface version, touched owners, exact commands, source
and toolchain identity, test vectors and evidence path. Format decoding is not
proof of deployment, setting a permission is not proof of effective access, and
an ad-hoc signature is not publisher authentication or notarization.

## Follow-on work

Advanced registry resolution, remote/distributed caches, cache quota collection,
complete Python/TypeScript/Go/Rust author packages, GUI, arbitrary ACL rules,
additional system integrations, bridge-release orchestration and publisher
qualification remain separate packages. They must reuse the established content,
authority, type and lifecycle boundaries. Every task requires an owner, fixed
input contract, non-goals, command, negative vector and retained evidence before
it can be reported complete.

## Parallel implementation handoff

All packages start from the active contracts in [the index](README.md). An owner is
a role to assign before implementation, not an invented person. Existing gates
below are runnable now. Commands marked **new gate** are required deliverables;
they must be registered in the build graph and `verify` before a package closes.
Each record goes to `.evidence/<suite>/<UTC>/` with source/tool identities, exact
commands, negative results and the actual final artifact digest.

### COMP-INC — Compiler incrementality and scheduling

- Owner: compiler maintainer. Dependencies: CORE-01/02/05 and compiler-frontends-v2.
- Interface baseline: normalized author model, resolved compiled input types,
  exact lock, source-map sidecar, stage diagnostics and inspector/finalizer hooks.
- Deliverables: normalization/inspection/assembly stage caches, bounded concurrent
  scheduling, detailed type/dependency diagnostics, cache leases/quotas and performance baseline.
- Non-goals: registry authorization, remote caches and product selection policy.
- Acceptance: existing `zig build compiler-v2-test core-test`; **new gate**
  `zig build compiler-incremental-test`. Compare clean/cached outputs for changed
  source bytes, logical content, library, tool, runtime, target, limits and maps;
  interrupt every publication boundary and cancel active workers.

### LIB-SDK — Library packages and author conveniences

- Owner: Component SDK maintainer. Dependencies: CORE-01/02/03/06.
- Interface baseline: capability-library-v2, standard WIT proposal package and fixed
  Component profile. Generated bindings remain upstream-owned.
- Deliverables: package inspection/publishing tools, independent test host,
  generated author conveniences, explicit unused-input type API and more guest languages.
- Non-goals: ambient WASI, native plugin discovery or serialized-engine caches.
- Acceptance: existing `zig build component-test author-v2-test core-e2e`;
  **new gate** `zig build library-package-test`. Independent consumers must prove
  exact values, version mismatches, lifetimes, resource boundaries and final setup output.

### HOST-EXT — Additional host operations and content capabilities

- Owner: primitive/platform maintainers. Dependencies: CORE-03/04/06 and the
  [four-family design](design/host-primitives-and-stdlib.md).
- Interface baseline: scoped grants, typed observations, durable resource identity,
  concrete plans and native receipts. Content mode remains separate from authority.
- Deliverables: streaming content access/derivation, finer per-entry access,
  environment/registration/service primitives and their stdlib wrappers.
- Non-goals: arbitrary shell execution, implicit privilege or shared-object adoption.
- Acceptance: existing `zig build access-test kernel-test core-e2e`;
  **new gate** `zig build primitive-conformance`. Every operation needs own/foreign
  identity, unsupported scope/filesystem, drift, partial failure, restore and real-kill vectors.

### AUTHOR-PY / AUTHOR-TS / AUTHOR-GO / AUTHOR-RS — Language packages

- Owners: one maintainer per language. Dependencies: CORE-01/05 and authoring-C-ABI-v2.
- Interface baseline: copied UTF-8/buffers, context-owned typed handles, source maps,
  ABI negotiation, stable status and backend-owned semantics.
- Deliverables: distributable package, idiomatic deterministic lifetime management,
  diagnostics, lossless integers and an independent consumer project per language.
- Non-goals: another semantic validator or a JSON/YAML author-expression language.
- Acceptance: existing `zig build author-v2-test`; **new gates**
  `zig build sdk-python-test`, `sdk-typescript-test`, `sdk-go-test`, `sdk-rust-test`.
  Each package must exercise foreign handles, cancellation, Unicode/binary/full-width
  values, clean release and a real equivalent setup. Source-map-only changes must not alter IR.

### PRODUCT-PRESETS — Components, SDKs and coexistence

- Owner: product-library maintainer. Dependencies: CORE-05/06 and LIB-SDK.
- Interface baseline: typed inputs/DAG, library contracts, exclusive roots and migration.
- Deliverables: component families, workloads, parallel version layouts, detection
  policy and selection migration through replaceable libraries/presets.
- Non-goals: component/channel enums in kernel or auto-installing detected prerequisites.
- Acceptance: existing `zig build core-e2e`; **new gate** `zig build preset-scenarios`.
  Execute the [product journeys](design/product-journeys.md): different product
  policies, selected/unselected artifacts, coexistence conflicts and independent shared objects.

### COMPAT — Multi-version and framework evolution

- Owner: compatibility maintainer. Dependencies: CORE-06, migration-v2 and PRODUCT-PRESETS.
- Interface baseline: immutable rule IDs/digests, direct transitions, owned call lineage,
  independent host/guest/product versions and guest-free recovery.
- Deliverables: explicit bounded multi-edge paths, optional-state converters,
  framework-format converters and product-declared bridge orchestration.
- Non-goals: inferred bridges, automatic replacement libraries or history rewriting.
- Acceptance: existing `zig build kernel-test core-e2e`; **new gate**
  `zig build migration-matrix`. Include old-format fixtures, ambiguous/missing paths,
  retired rules, changed checksums, converter failure and every intermediate crash state.

### DIST-TRUST — Acquisition, channels and publication

- Owner: distribution/trust maintainer. Dependencies: CORE-03/05/06 and versioned source primitives.
- Interface baseline: distinct source/logical/final identities; retained TUF crypto
  remains governed by its own contract until adapted.
- Deliverables: online/offline sources, authorized cache, channels, promotion,
  publisher history and final-byte release provenance.
- Non-goals: treating digest identity or ad-hoc signing as publisher authorization.
- Acceptance: existing retained trust/transfer suites plus **new gate**
  `zig build distribution-v2-test`. Exercise expiry/rollback, partial transfer,
  altered bytes, offline absence, key rotation and promotion without rebuilding.

### NATIVE-RELEASE — Profiles, signing and publisher automation

- Owner: native-image/release maintainer. Dependencies: CORE-07/08 and DIST-TRUST where applicable.
- Interface baseline: setup-image-v2, loaded descriptor/native-prefix measurement,
  separate runtime packages and locked host signing tools.
- Deliverables: published profile matrix, explicit minimum OS/toolchain metadata,
  publisher finalizers, notarization, additional native variants and release automation.
- Non-goals: product-stage runtime compilation or assuming cross-build equals target qualification.
- CPU publication follow-up: implement [proposed ADR-0025](adr/0025-baseline-cpu-runtime-publication.md)
  across the Zig graph, Rust/C-helper code generation and runtime/SDK metadata.
  Record the complete minimum CPU requirements and supplied-archive provenance;
  reject undeclared host-specific overrides. Acceptance must inspect emitted
  commands and run the final bytes on the declared minimum CPU context. Until
  then, native publisher results remain specific to their recorded host CPU.
- Acceptance: existing `zig build image-test core-e2e core-cross-tools`; **new gate**
  `zig build release-profile-test`. Test final delivered bytes, prefix/code/payload
  tampering, wrong templates, signing interruption and each selected publisher policy.

### UI-EMBED — UI and application maintenance

- Owner: UI/embedding maintainer. Dependencies: CORE-06, typed input/state contracts and
  [ADR-0008](adr/0008-shared-software-renderer.md).
- Interface baseline: immutable input schema, observable state/progress and authorized operations.
- Deliverables: GUI/CLI semantic parity, accessible workflows, cancellation and embedded maintenance.
- Non-goals: native-widget replacement of the shared renderer or UI-owned mutation authority.
- Acceptance: retained UI/golden gates plus **new gate** `zig build runtime-ui-test`.
  Compare real resources and state across frontends, keyboard/screen-reader behavior,
  cancellation and recovery. Visual snapshots alone are insufficient.

### QUALIFY — Platform and identity matrix

- Owner: platform qualification maintainer. Dependencies: delivered packages above.
- Interface baseline: every claim names OS/version, architecture/emulation, scope,
  filesystem, privilege context and exact runtime/setup identities.
- Deliverables: native x64 CI/hardware records, additional filesystem/ACL support,
  machine scope and independent-identity permission evidence.
- Windows temporary-executable cleanup: identify the native error and image/handle lifetime
  behind the observed non-admin NTFS `AccessDenied` warning, then remove owned worker
  snapshots after execution. The current x64-on-Arm64 witness passes lifecycle/state
  assertions but retains private executable copies after uninstall. Keep this limitation
  visible until the cause is established; do not substitute elevation, broader ACLs or
  blind retries. Acceptance must show zero retained worker snapshots, preserved lifecycle
  results and exact final-image identities in each claimed context.
- Non-goals: promoting a compile result or another OS's test to a support claim.
- Acceptance: `zig build core-test verify`, the isolated Linux assembly witness,
  transferred-image witness and `vm-smoke` where its scenario contract applies.
  Every added matrix cell must include unsupported outcomes and real process termination.

Independent SDK, content, platform and policy packages can proceed in parallel
once their versioned inputs are fixed. Changes to shared semantics update the
contract and conformance vectors first, then downstream packages. Integration
owners review the resulting graph, rather than resolving conflicts through
frontend-specific defaults or new kernel policy fields.
