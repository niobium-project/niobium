# Module boundaries

`build/modules.zig` owns actual registrations and allowed imports. The compiler enforces those imports; repository checks reject cross-owner relative imports. This page records the target ownership and disposition of existing modules.

## Target dependencies

| Owner | Permitted dependencies | Boundary |
|---|---|---|
| Author frontends | Compiler/program public API | Build-time only |
| Compiler | Program, profile validation, core/contracts | No product-specific runtime build |
| Runtime | Program, Wasm host, host/platform, core/contracts | No compiler/frontend/preset dependency |
| Capability library | Public guest SDK and linked guest code | No native implementation import |
| Program/profile contracts | Core/contracts | No platform effects |
| Host/platform | Core/contracts and declared native dependencies | Checked effects and recovery |
| Presets/author stdlib | Public author API and library contracts | Product policy stays here |

Wasm modules cross a versioned host ABI, not Zig module imports. Runtime profiles bind the available primitives. The [host design](../design/host-primitives-and-stdlib.md) defines the authority and lifecycle contract.

## Existing module disposition

| Existing owner | Disposition | Target responsibility |
|---|---|---|
| `core` | Reuse | Bounded utilities with explicit allocator/IO |
| `contracts` | Adapt | Shared limits and strict decoding; legacy product types remain scoped |
| `manifest` | Retain for legacy; retire after consumers migrate | New product model belongs to `program` |
| `packager`, `build/sdk.zig` | Adapt selected mechanics; retain old API as legacy | Compiler image/artifact tooling, then author SDK |
| `engine` | Retain for legacy | Runtime mechanics separate from standard deployment policy |
| `resolver` | Move policy to distribution/product libraries | Release/channel/component selection |
| `planner` | Split mechanisms and policy | Frozen host plan versus deployment convention |
| `transaction` | Reuse proven mechanics with new evidence | Durable operation/recovery contract |
| `executor` | Adapt | Host primitive execution and receipts |
| `platform` | Reuse and adapt per primitive | OS mechanics and explicit scope/target support |
| `privilege` | Adapt after user-scope PoC | Closed privileged host operations |
| `trust` | Reuse cryptographic mechanics; library owns release policy | Verification and authorization |
| `repository` | Adapt | Authorized source primitives and distribution library |
| `package` | Reuse strict extraction; separate artifact policy | Safe extraction host mechanism |
| `bootstrap` | Adapt through explicit activation contract | Product business initialization and pending behavior |
| `portable` | Move policy to standard library | Portable deployment profile |
| `conformance` | Extend alongside new ABI vectors | Primitive/backend qualification |
| `ui/core`, `ui/kit`, `ui/tokens`, `ui/render` | Reuse | Pure model, components and renderer |
| `ui/screens`, `ui/backend` | Adapt boundary as needed | Standard workflow and native presentation |
| `apps/setup`, `apps/nbpack`, `apps/libdistribution` | Retain for legacy | Historical process interfaces and regressions |
| `apps/ui-workbench` | Reuse | Standard UI development tooling |
| `third_party` | Reuse dependency/provenance discipline | Pinned Component toolchain plus retained WAMR and other dependencies |
| `tools`, `tests` | Extend | N2 contract checks and evidence without removing N1 regressions |

## Standard-core owners

| Owner | Responsibility | Dependency constraint |
|---|---|---|
| `tar` | Shared pure tar codec and generic fixtures | No platform or product policy |
| `content` | Logical trees, canonical containers and transformations | Contracts plus pure tar; no native deployment |
| `program` | Author/compiled model, WIT descriptors, values and profiles | Shared contracts/content only |
| `compiler` | Author SDK and common compilation stages | Build-time phase; no product runtime relink |
| `image` | Native carrier inspection, assembly and measurement | Shared bounded sources; signing invocation stays in the application |
| `component_engine` | Pinned upstream engine bridge | Upstream boundary only |
| `component_worker` | Standard ABI inspection/evaluation | Shared program contract and engine, no frontend |
| `component_client` | Disposable fixed-worker process lifetime | Shared protocol; no engine/native guest memory |
| `host_primitives` | Published observation and primitive contracts | No component/workload/channel policy |
| `evaluator` | Typed graph evaluation and proposal normalization | Install-time; no compiler/frontend |
| `access_policy`, `access` | Portable intent and native discretionary access | Pure contract separated from platform bridge |
| `kernel` | Ownership, frozen operations, commit and recovery | Install-time; no library/preset policy |
| `runtime_process` | Complete precompiled runtime entrypoint | Registered install-time root; transitive phase guards include app assembly |
| `stdlib/files` | Optional file deployment and content selection | Public WIT only; built as an independent Component |

`apps/compiler-v2`, `apps/libcompiler/v2.zig` and `apps/starlark/v2` assemble host
entrypoints. `apps/runtime-v2` consumes the registered `runtime_process` graph.
The Core Wasm owners `wasm_profile`, `wasm_host` and `runtime` remain v1 implementations.
All platform support claims require their own current acceptance evidence.

## Enforced boundaries

`ui/core` and `ui/kit` cannot depend on engine, platform or IO. Current standard screens use `contracts` for their engine-facing model. Runtime/library changes must not leak through that UI contract implicitly.

Process spawn and pointer-cast exceptions are enumerated in `build/modules.zig`, with reasons for each new bridge. Guest pointers require bounds validation before native translation. Adding a new module is not permission to bypass the contract graph.

Runtime's transitive graph must exclude compiler, author frontends and presets. Kernel schemas must not grow component-family, channel or SDK policy fields. A library requiring a new primitive requests a versioned host contract before implementation.
