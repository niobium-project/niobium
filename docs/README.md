# Documentation index

Maintainer documents define the DSL/AOT toolchain under [ADR-0022](adr/0022-installer-dsl-and-aot-toolchain.md). [AGENTS.md](../AGENTS.md) owns development constraints. Product-author documentation lives in [apps/user-docs](../apps/user-docs/README.md).

## Active contracts

These specifications own new interfaces. Normative targets and execution evidence are distinct; implementation status belongs to [N2 acceptance](acceptance-plan-v0.2.md).

| Contract | Specification | Interface owner |
|---|---|---|
| Authoring and compiler | [compiler-frontends-v1](spec/compiler-frontends-v1.md) | `libs/compiler`, `api/c/compiler.h` |
| Compiled program and carrier | [program-image-v1](spec/program-image-v1.md) | `libs/program`, [schema](../api/schema/compiled-program-v1.schema.json) |
| Capability library | [capability-library-v1](spec/capability-library-v1.md) | `api/c/capability.h`, `libs/wasm_profile`, `libs/wasm_host` |
| Host lifecycle | [runtime-lifecycle-v1](spec/runtime-lifecycle-v1.md) | `libs/runtime`, [state schema](../api/schema/runtime-state-v1.schema.json), [plan schema](../api/schema/runtime-plan-v1.schema.json) |
| Compatibility and migration | [migration-v1](spec/migration-v1.md) | Program, library and host state owners |
| Test execution and archived evidence | [test-system-v1](spec/test-system-v1.md) | `api/schema/test-report-v1.schema.json` |

## Design and implementation

| Purpose | Document |
|---|---|
| Compiler phases, dependencies, cache, diagnostics and SDKs | [Compiler engineering](design/compiler-engineering.md) |
| Guest SDK, ABI, packages and conformance | [Wasm library SDK](design/wasm-library-sdk.md) |
| Authority, host effects, stdlib and policy | [Host primitives and standard libraries](design/host-primitives-and-stdlib.md) |
| Current architecture and code ownership | [Overview](architecture/overview.md), [module boundaries](architecture/module-boundaries.md) |
| Transaction and recovery implementations | [Transaction model](architecture/transaction-model.md) |
| Standard UI | [UI engine](architecture/ui-engine.md) |
| Work packages and dependencies | [Roadmap v0.2](roadmap-v0.2.md) |
| N2 execution evidence | [Acceptance plan v0.2](acceptance-plan-v0.2.md) |
| Decisions and amendments | [ADR index](adr/README.md) |

## Development

| Purpose | Document |
|---|---|
| Documentation lifecycle | [Documentation management](development/docs-management.md) |
| Build and run the two-release PoC | [DSL/AOT workflow](development/aot-poc.md) |
| Directory and owner rules | [Repository layout](development/repository-layout.md) |
| Test lanes and evidence | [Testing lanes](development/testing-lanes.md), [construction state](roadmap-v0.2.md#test-system-construction) |
| Online, complete offline-file and SFX delivery | [Distribution backlog](development/distribution-backlog.md), [ADR-0020](adr/0020-distribution-delivery-milestones.md) |
| CI evidence transport | [ADR-0021](adr/0021-ci-evidence-transport.md), [deployment and recovery](development/testing-lanes.md#r2-deployment-and-recovery) |
| Checks, lint and skills | [Tooling and rules](development/tooling-and-rules.md) |
| UI component lifecycle | [UI lifecycle](development/ui-component-lifecycle.md) |
| Commit conventions | [Commits](development/commits.md) |
| Product consumer boundary and legacy API | [Consuming](development/consuming.md) |
| Signing, key rotation, offline bundles and real OS testing | [Runbooks](runbooks/) |
| Platform tier obligations | [ADR-0014](adr/0014-tier-based-platform-support.md) |
| Feature coverage disposition | [Feature coverage](feature-coverage.md) |

## Retained v1 contracts and records

These documents apply to the legacy implementation and retained subsystems. Their product authoring and closed-extension assumptions do not constrain the active DSL contracts. Reuse requires the tests of the new owning contract.

| Area | Documents |
|---|---|
| Product and artifact formats | [Manifest](spec/manifest-v1.md), [component](spec/component-v1.md), [artifact](spec/artifact-format-v1.md) |
| Distribution trust and activation | [TUF](spec/tuf-profile-v1.md), [Bootstrap](spec/bootstrap-v1.md) |
| Legacy process interfaces | [CLI](spec/cli-v1.md), [IPC](spec/ipc-v1.md), [C ABI](spec/abi-v1.md) |
| Retained UI/platform contracts | [UI IR](spec/ui-ir-v1.md), [platform](spec/platform-contract-v1.md) |
| Legacy product scope and shared testing evidence | [Roadmap v0.1](roadmap-v0.1.md), [N1 acceptance and test-system evidence](acceptance-plan-v0.1.md) |
| Read-only architecture input | [Source v0.1](source/architecture-v0.1.md), [source v0.2](source/architecture-v0.2.md) |

Status vocabulary is `PASS`, `FAIL`, `BLOCKED`, `NOT_RUN`, `DEFERRED`. Optional dated implementation traces are not sources of truth.
