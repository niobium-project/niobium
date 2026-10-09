# Documentation index

Niobium is an installation/distribution DSL and AOT toolchain under
[ADR-0022](adr/0022-installer-dsl-and-aot-toolchain.md), amended by
[ADR-0023](adr/0023-standard-content-and-component-contracts.md) for standard
content, WIT Components and cross-host assembly. [AGENTS.md](../AGENTS.md) owns
hard development constraints. Product-author documentation lives in
[apps/user-docs](../apps/user-docs/README.md). The
[DSL tutorial](../apps/user-docs/src/content/docs/tutorial/index.md) teaches
Starlark product authoring through a runnable installation and update example.

[ADR-0024](adr/0024-native-runtime-dependency-qualification.md) defines native
runtime dependency qualification by OS and ABI, separately from retained binaries.
[ADR-0025](adr/0025-baseline-cpu-runtime-publication.md) defines CPU baselines for
published runtimes and SDK artifacts.
[ADR-0026](adr/0026-pinned-rust-component-wasm.md) keeps the Component engine
and repository-owned guests on pinned Rust until a competing alternative is
qualified.
[ADR-0027](adr/0027-zig-provisioned-host-tools.md) has Zig install the Rust and
Go tools that build and test use.

## Active contracts

Normative requirements, current implementation and execution evidence are distinct.
[Acceptance v0.3](acceptance-plan-v0.3.md) records the current standard-core profile.

| Contract owner | Specifications | Interfaces |
|---|---|---|
| Compiler and authoring | [Compiler/frontends v2](spec/compiler-frontends-v2.md), [authoring C ABI v2](spec/authoring-c-abi-v2.md), [locked inputs/cache](spec/compiler-inputs-v1.md) | `compiler.author`, `compiler.pipeline`, `compiler_v2.h`, source-map schema |
| Compiled product and native image | [Product v2](spec/program-image-v2.md), [setup image v2](spec/setup-image-v2.md), [content container v1](spec/content-container-v1.md), [runtime package v2](spec/runtime-package-v2.md) | `program`, `content`, `image`, compiled-product/value/type/runtime-package schemas |
| Capability library | [Capability library v2](spec/capability-library-v2.md) | Versioned WIT, upstream bindings and Component profile |
| Runtime lifecycle | [Lifecycle v2](spec/runtime-lifecycle-v2.md), [access policy v1](spec/access-policy-v1.md) | `kernel`, `evaluator`, host primitives and native receipts |
| Migration | [Migration v2](spec/migration-v2.md) | Independent program, call-state and frozen-plan compatibility |
| Test execution and evidence | [Test system v1](spec/test-system-v1.md) | Test-report schema and archived producer records |

## Design and implementation

| Purpose | Document |
|---|---|
| Compiler phases, dependencies, incremental work, diagnostics and SDKs | [Compiler engineering](design/compiler-engineering.md) |
| Library packages, generated bindings and conformance | [Wasm library SDK](design/wasm-library-sdk.md) |
| Four primitive families, grants, lifecycle and policy ownership | [Host primitives and stdlib](design/host-primitives-and-stdlib.md) |
| Product scenarios, objects, operations and negative cases | [Product journeys](design/product-journeys.md), [feature coverage](feature-coverage.md) |
| Current code and dependency ownership | [Overview](architecture/overview.md), [module boundaries](architecture/module-boundaries.md) |
| Transaction/recovery implementations | [Transaction model](architecture/transaction-model.md) |
| Standard UI | [UI engine](architecture/ui-engine.md) |
| Parallel work packages, dependencies and acceptance commands | [Roadmap v0.3](roadmap-v0.3.md) |
| Current execution evidence | [Acceptance v0.3](acceptance-plan-v0.3.md) |
| Decisions and amendments | [ADR index](adr/README.md) |

## Development

| Purpose | Document |
|---|---|
| Current typed author APIs and Starlark | [Authoring v2](development/authoring-v2.md) |
| Independent Component library development | [Component library SDK](development/component-library-sdk.md) |
| Runtime publishing and cross-host assembly | [Cross-host workflow](development/cross-host-builds.md) |
| Documentation lifecycle | [Documentation management](development/docs-management.md) |
| Directory and owner rules | [Repository layout](development/repository-layout.md) |
| Test lanes and evidence | [Testing lanes](development/testing-lanes.md) |
| Checks, lint and skills | [Tooling and rules](development/tooling-and-rules.md) |
| UI component lifecycle | [UI lifecycle](development/ui-component-lifecycle.md) |
| Commit and pull request rules | [Commits and pull requests](development/commits.md) |
| Consumer boundaries and retained APIs | [Consuming](development/consuming.md) |
| Distribution backlog | [Distribution milestones](development/distribution-backlog.md), [ADR-0020](adr/0020-distribution-delivery-milestones.md) |
| CI evidence transport | [ADR-0021](adr/0021-ci-evidence-transport.md), [deployment/recovery](development/testing-lanes.md#r2-deployment-and-recovery) |
| Operational procedures | [Runbooks](runbooks/) |
| Platform tiers | [ADR-0014](adr/0014-tier-based-platform-support.md) |

## Retained contracts and records

Retained implementations keep their original formats, test lanes and evidence.
Reuse at a new boundary requires new acceptance; historical claims do not transfer.

| Area | Documents |
|---|---|
| Core Wasm v1 DSL/AOT profile | [Compiler](spec/compiler-frontends-v1.md), [program/image](spec/program-image-v1.md), [capability ABI](spec/capability-library-v1.md), [runtime](spec/runtime-lifecycle-v1.md), [migration](spec/migration-v1.md) |
| Core Wasm v1 workflow and delivery | [PoC guide](development/aot-poc.md), [roadmap v0.2](roadmap-v0.2.md), [acceptance v0.2](acceptance-plan-v0.2.md) |
| Manifest-era formats | [Manifest](spec/manifest-v1.md), [component](spec/component-v1.md), [artifact](spec/artifact-format-v1.md) |
| Distribution trust and activation | [TUF](spec/tuf-profile-v1.md), [Bootstrap](spec/bootstrap-v1.md) |
| Retained process interfaces | [CLI](spec/cli-v1.md), [IPC](spec/ipc-v1.md), [C ABI](spec/abi-v1.md) |
| Retained UI/platform contracts | [UI IR](spec/ui-ir-v1.md), [platform](spec/platform-contract-v1.md) |
| Earlier product scope and shared testing evidence | [Roadmap v0.1](roadmap-v0.1.md), [N1 acceptance](acceptance-plan-v0.1.md) |
| Read-only original architecture input | [Source v0.1](source/architecture-v0.1.md), [source v0.2](source/architecture-v0.2.md) |

Status vocabulary is `PASS`, `FAIL`, `BLOCKED`, `NOT_RUN`, `DEFERRED`.
Optional dated implementation traces are not sources of truth.
