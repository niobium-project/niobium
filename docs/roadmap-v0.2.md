# Roadmap v0.2: DSL/AOT toolchain

The delivery baseline is [ADR-0022](adr/0022-installer-dsl-and-aot-toolchain.md), its five active specifications, and the detailed compiler, library SDK and host/stdlib designs. This roadmap owns implementation sequencing and handoff; [N2 acceptance](acceptance-plan-v0.2.md) owns results.

## Current delivery

The current delivery includes architecture/governance alignment, complete designs for the three engineering areas, and an executable macOS arm64 user-scope CLI PoC. The PoC must connect native/C/Starlark authoring, a shared compiler, one precompiled runtime, official/external Wasm libraries, explicit migration and crash recovery.

Detailed designs delivered with this baseline:

- [Compiler engineering](design/compiler-engineering.md): phases, APIs, lockfile, caching, incremental invalidation, diagnostics, concurrency and output publication.
- [Wasm library SDK](design/wasm-library-sdk.md): contracts, ABI, package structure, ownership, state and conformance tooling.
- [Host primitives and standard libraries](design/host-primitives-and-stdlib.md): authority, lifecycle, platform matrix, extension process and policy ownership.

The PoC implements a bounded vertical slice of those designs. It does not imply that registry resolution, cache tooling, all guest languages or all host primitives are implemented. The [module disposition table](architecture/module-boundaries.md) assigns existing code to its target owner.

## Work packages

Each package has a role owner, fixed input contracts and completion evidence. One engineer or agent claims that role before changing code. Shared contract changes require a versioned contract and updated vectors before dependent implementations merge.

| Package | Owner role | Dependencies | Public boundary | Deliverable | Acceptance |
|---|---|---|---|---|---|
| WP-01 Compiler backend | Compiler maintainer | Current program/frontend/image contracts | Compiler API and diagnostic schema | Locked dependency resolver, provenance, stage cache, incremental invalidation, cancellation | N2-COMPILER-01 |
| WP-02 Language SDKs | One maintainer per language | Authoring C ABI and frontend vectors | Python/TS/Go/Rust packages | Idiomatic ownership, diagnostics, package release and example setup | N2-SDK-01 per language |
| WP-03 Library SDK | Capability SDK maintainer | Capability ABI and profile vectors | Guest bindings and package descriptor | Contract generation, package inspection, conformance runner and test host | N2-WSDK-01 |
| WP-04 Host primitives | One maintainer per primitive/backend | Runtime lifecycle and host design | Versioned host operation/profile | File/registration/service/environment implementations and recovery receipts | N2-HOST-01 per operation/target/scope |
| WP-05 Standard libraries/presets | Product model maintainer | Existing host primitives and author API | Author-library and capability contracts | Component families, workloads, optional modules, toolchain coexistence and themes | N2-PRESET-01 |
| WP-06 Compatibility | Migration maintainer | Migration and host plan contracts | Migration history, bridge and format readers | Multi-version paths, immutable rule history, framework compatibility and bridge orchestration | N2-COMPAT-01, N2-BRIDGE-01 |
| WP-07 Distribution/trust | Distribution maintainer | Program identities and host authority | Sources, cache, trust and channel library contracts | Adapt existing verified acquisition, TUF and publishing behavior | N2-DIST-01 |
| WP-08 Native images | Image/release maintainer | Image backend and provenance contracts | Runtime profile and image backend | Larger Mach-O payloads, PE/ELF, publisher signing and runtime distributions | N2-NATIVE-01 |
| WP-09 UI/embedding | UI/API maintainer | Runtime lifecycle inputs/state/events | Standard UI and embedding API | Shared CLI/GUI semantics, application maintenance, cancellation and accessibility | N2-UI-01 |
| WP-10 Qualification | Platform maintainer | Specific delivered packages | Per-target qualification matrix | Real OS, machine scope, final signatures and release validation | N2-PLATFORM-01 |

## Package acceptance and non-goals

| Package | Required tests and evidence | Excluded changes |
|---|---|---|
| WP-01 | Clean versus cached output equality; changed assets/model/runtime/source map; corrupt cache; cancellation and disk-full publication; locked offline miss | Runtime registry resolution or product policy defaults |
| WP-02 | Shared vectors, UTF-8/large integers, failed builder operations, lifetime and actual setup execution; platform package install | Language-specific semantics or a second compiler backend |
| WP-03 | Standalone external package through production profile/host; imports, memory, trap, budget, duplicate output and migration failures | Ambient WASI or native extension loading |
| WP-04 | Per-operation apply/verify/rollback, every durable interruption, ownership collision, unsupported target and real backend conformance | Generic shell/process APIs or unjournaled side effects |
| WP-05 | Different single/multi-version policies on identical kernel; explicit selection migration; missing rule refusal | Component/channel enums in the kernel |
| WP-06 | Complete/absent/ambiguous paths; applied rule changes; unsupported host schemas; each authorized bridge leg and interrupted resume | Guessing compatibility from version names or automatic database rollback |
| WP-07 | Tampered/expired/rolled-back metadata, offline equivalence, fixed library identity, interrupted fetch and publish | Bypassing trust to satisfy a migration path |
| WP-08 | Same template code across products, capacity limits, malformed carriers, final signature and execution per native format | Relinking product-specific runtimes |
| WP-09 | Identical choices/plan to CLI; cancel/failure/progress; accessibility semantics and real embedded host | UI-specific transaction authority |
| WP-10 | Final bytes on declared OS/architecture/scope; signing, elevation cancellation and recoverability | Promoting cross-compile or virtual-platform evidence to real OS |

Existing commands remain part of package verification: `zig build check test`, `zig build verify`, and the applicable `sim`, `fuzz`, `cross`, `check-binary`, `size-gate`, `golden` or `vm-smoke` lane. Each new package adds a named runnable conformance/e2e target to the build graph before declaring completion.

The PoC commands are `zig build aot`, `zig build aot-test` and `zig build aot-e2e`. Package handoff records the exact command and target used; the command list is not a claim that every platform has run it.

## Parallel execution and integration

WP-01, WP-02, WP-03 and WP-08 can begin against the frozen contracts independently. WP-04 splits by primitive and platform after its operation contract is fixed. WP-05 and WP-07 use existing primitives first and request new versioned primitives through WP-04.

WP-06 can implement pure path/history validation independently; bridge acquisition depends on WP-07. WP-09 can develop its read-only state/input adapter independently of new primitive implementations. WP-10 qualifies completed slices and preserves an explicit NOT_RUN entry for each untested combination.

A handoff contains the owning spec version, touched modules, dependency identities, positive/negative vectors, exact build commands, evidence location and remaining limitations. Review checks source boundaries and contract drift before the combined `verify` run. Parallel implementation does not authorize duplicate contract owners.

## Retained work

The historical [N1 plan](acceptance-plan-v0.1.md) retains its machine-scope, GUI and VM gaps. They remain useful regression work but do not transfer statuses into N2. The read-only [source architecture](source/architecture-v0.2.md) remains background rather than current requirements.

Publisher key rotation, security reporting, UI localization, additional desktop platforms and accessibility platform bridges stay in their corresponding distribution, UI or qualification package. Native Wayland remains outside the current platform direction under ADR-0010.

## Distribution delivery milestones

[ADR-0020](adr/0020-distribution-delivery-milestones.md), amended by ADR-0022,
retains online, complete offline-file and SFX delivery. The
[distribution backlog](development/distribution-backlog.md) owns DIST-01 through
DIST-11. Its tasks map to WP-07 (sources/trust), WP-08 (containers/signing), WP-04
(host effects) and WP-10 (qualification). No task is closed by the bounded PoC
unless its complete release-level criteria have independent evidence.

## Test-system construction

This shared test-system work retains its own evidence and construction scope. N1
product scenarios remain specific to the legacy engine; they do not qualify N2
product behavior. The DSL/AOT lanes must preserve the catalog and archive protocol
when they integrate with this infrastructure.

The [test-system specification](spec/test-system-v1.md) owns the contract. This table tracks
construction, separately from execution verdicts. `supported` means repeatable evidence for the
named scope; `working` means implementation has gaps with exit criteria; `not yet supported`
means planned with prerequisites; `not planned` means deliberately excluded. Target assignments
remain in [Platform support](../apps/user-docs/src/content/docs/platforms.md); tier obligations
remain in [ADR-0014](adr/0014-tier-based-platform-support.md).

| Capability | Applicable environments | Acceptance IDs | Construction | Remaining work / exit criteria | Evidence |
|---|---|---|---|---|---|
| Parameterized execution, compatibility aliases | macOS local catalog; hosted Ubuntu/Windows/macOS unit/conformance/e2e | N1-AC-20 | supported | Current runs remain required; other native suite/target combinations need their own evidence | [Validation](acceptance-plan-v0.1.md#test-system-validation-2026-10-07) |
| Structured reports and bounded capture | Same hosts; suite aggregates and conformance/e2e cases | N1-AC-20 | supported | Current runs remain required; other lanes retain suite outcomes without unavailable case evidence | [Deployment validation](acceptance-plan-v0.1.md#r2-deployment-validation-2026-10-08) |
| Independent lifecycle probes | Hosted Ubuntu/Windows/macOS, user scope; disposable Windows account | N1-UJ-01, N1-UJ-03, N1-UJ-04, N1-UJ-05, N1-UJ-06, N1-UJ-07, N1-INV-05, N1-INV-06 | supported | Current run required; native elevation/desktop excluded from this scope | [Validation](acceptance-plan-v0.1.md#test-system-validation-2026-10-07) |
| Platform contract | Hosted Ubuntu/Windows/macOS, redirected user/machine roots | N1-AC-14 | supported | Current run required; registry/service-manager exclusions remain explicit NOT_RUN contracts | [Validation](acceptance-plan-v0.1.md#test-system-validation-2026-10-07) |
| Fault simulation and corpus replay | VirtualPlatform on native hosts | N1-AC-07, N1-INV-05 | working | macOS 2,000-seed replay and corpus passed; hosted evidence remains | [Local validation](acceptance-plan-v0.1.md#test-system-validation-2026-10-07) |
| Native continuous fuzz | Zig native protocol on macOS/Linux | N1-INV-02, N1-INV-05 | working | Resolve missing sanitizer symbols during zstd fuzz rebuild on macOS; exploration has no archive verdict | [Local validation](acceptance-plan-v0.1.md#test-system-validation-2026-10-07) |
| Durable R2 history | Trusted Ubuntu publisher; private configured US bucket | N1-AC-20 | supported | Renew monthly retention horizon before September 2027 ends; preserve current-run and platform obligations | [Deployment validation](acceptance-plan-v0.1.md#r2-deployment-validation-2026-10-08) |
| GUI automation and visual services | Future reference desktops | N1-UJ-10 | not yet supported | Desktop drivers and accessibility bridges; software golden remains separate | [UI lanes](development/testing-lanes.md#ui-golden) |
| Native permissions/elevation | Reference OS in the platform strategy | N1-UJ-02, N1-AC-18, N1-AC-19 | not yet supported | Real elevation, service managers and reference OS; redirected conformance cannot close these | [VM runbook](runbooks/vm-smoke.md) |
| Final signed release verification | Released Tier 1 targets | N1-AC-20 | not yet supported | Signing inputs, tests of final bytes and retained release bundles | [Signing runbook](runbooks/release-signing.md) |
| Container and VM orchestration | Future isolated Linux / reference OS | N1-AC-20 | not yet supported | Separate execution project; existing explicit vm-smoke retained | [VM runbook](runbooks/vm-smoke.md) |
| Results viewer | Archive readers | N1-AC-20 | not yet supported | Separate task; paginated object protocol supplies history | [Archive contract](spec/test-system-v1.md#report-and-archive) |
| Database, mutable latest index, custom S3 signing | Archive | N1-AC-20 | not planned | Immutable object listing and pinned transport cover the current need | [ADR-0021](adr/0021-ci-evidence-transport.md) |
