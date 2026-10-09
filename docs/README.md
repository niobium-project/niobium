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
runtime dependency qualification by OS and ABI, separately from independent component checks.
[ADR-0025](adr/0025-baseline-cpu-runtime-publication.md) defines CPU baselines for
published runtimes and SDK artifacts.
[ADR-0026](adr/0026-pinned-rust-component-wasm.md) keeps the Component engine
and repository-owned guests on pinned Rust until a competing alternative is
qualified.
[ADR-0027](adr/0027-zig-provisioned-host-tools.md) has Zig install the Rust and
Go tools that build and test use.

## Active contracts

Normative requirements, current implementation and execution evidence are distinct.
[Acceptance ](acceptance-plan.md) records the current standard-core profile.

| Contract owner | Specifications | Interfaces |
|---|---|---|
| Compiler and authoring | [Compiler/frontends](spec/compiler-frontends.md), [authoring C ABI](spec/authoring-c-abi.md), [locked inputs/cache](spec/compiler-inputs.md) | `compiler.author`, `compiler.pipeline`, `compiler.h`, source-map schema |
| Compiled product and native image | [Product](spec/program-image.md), [setup image](spec/setup-image.md), [content container](spec/content-container.md), [runtime package](spec/runtime-package.md) | `program`, `content`, `image`, compiled-product/value/type/runtime-package schemas |
| Capability library | [Capability library](spec/capability-library.md) | Versioned WIT, upstream bindings and Component profile |
| Runtime lifecycle | [Lifecycle](spec/runtime-lifecycle.md), [access policy](spec/access-policy.md) | `kernel`, `evaluator`, host primitives and native receipts |
| Migration | [Migration](spec/migration.md) | Independent program, call-state and frozen-plan compatibility |
| Test execution and evidence | [Test system](spec/test-system.md) | Test-report schema and archived producer records |

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
| Parallel work packages, dependencies and acceptance commands | [Roadmap ](roadmap.md) |
| Current execution evidence | [Acceptance ](acceptance-plan.md) |
| Decisions and amendments | [ADR index](adr/README.md) |

## Development

| Purpose | Document |
|---|---|
| Current typed author APIs and Starlark | [Authoring](development/authoring.md) |
| Independent Component library development | [Component library SDK](development/component-library-sdk.md) |
| Runtime publishing and cross-host assembly | [Cross-host workflow](development/cross-host-builds.md) |
| Documentation lifecycle | [Documentation management](development/docs-management.md) |
| Directory and owner rules | [Repository layout](development/repository-layout.md) |
| Test lanes and evidence | [Testing lanes](development/testing-lanes.md) |
| Checks, lint and skills | [Tooling and rules](development/tooling-and-rules.md) |
| UI component lifecycle | [UI lifecycle](development/ui-component-lifecycle.md) |
| Commit conventions | [Commits](development/commits.md) |
| Distribution backlog | [Distribution milestones](development/distribution-backlog.md), [ADR-0020](adr/0020-distribution-delivery-milestones.md) |
| CI evidence transport | [ADR-0021](adr/0021-ci-evidence-transport.md), [deployment/recovery](development/testing-lanes.md#r2-deployment-and-recovery) |
| Platform tiers | [ADR-0014](adr/0014-tier-based-platform-support.md) |


## Independent components

These contracts describe tested components that are not integrated into the current
runtime: [TUF trust](spec/tuf-profile.md), [safe tar.zst extraction](spec/artifact-format.md),
[closed helper protocol](spec/ipc.md), [platform profiles](spec/platform-contract.md)
and [UI IR](spec/ui-ir.md). Their evidence retains its declared scope.

[Architecture review](architecture/review.md) records maintenance findings and
recommendations. These recommendations do not implement additional refactoring.

Status vocabulary: `PASS`, `FAIL`, `BLOCKED`, `NOT_RUN`, `DEFERRED`.
