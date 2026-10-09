# Acceptance plan: Standard core infrastructure

This plan owns the standard Component/product-v2 profile under
[ADR-0023](adr/0023-standard-content-and-component-contracts.md).
Independent component and shared test-system records retain their original scope;
their historical results do not qualify changed source or current products.

Status is `PASS`, `FAIL`, `BLOCKED`, `NOT_RUN` or `DEFERRED`. Implementation,
compilation, isolated conformance and target execution are separate claims.
A target claim records OS/version, CPU/emulation, filesystem and privilege scope.

## Current gates

`zig build test:core` is a dependency of `verify`. It includes typed model and
compiler tests, author/C/Starlark conformance, Component engine/IPC limits,
content interoperation, image assembly, native access, kernel recovery and the
complete native `core-e2e` lane. `core-cross-tools` builds the isolated assembly
and transferred-image witnesses; the cross-host run additionally needs published
templates and an isolated Linux environment. It cannot be inferred from a local
format test.

The rows below are registered for final source qualification. Intermediate
producer records remain in `.evidence/`; a row is updated only with an actual
record covering its required scenarios on the named snapshot.

## Standard-core cases

| ID | Description | Coverage | Status | Evidence |
|---|---|---|---|---|
| N2-ACCESS-01 | positive grants have one cross-platform interpretation | `libs/access/contract/root.zig`, `tests/access/` | PASS | `.evidence/final-v2/20261008T194056Z`; `.evidence/native-platform/20261008T144729Z`, `20261008T145621Z` |
| N2-BINARY-01 | Exact Component native dependency profiles, ELF interpreters and unchanged executable hardening | `tools/check-binary`, runtime publication gates | PASS | `.evidence/native-binary/20261008T160447Z-profiles`; `.evidence/final-v2/20261008T194056Z` |
| N2-CPU-01 | Explicit CPU targets and controlled Rust/C/Go flags cover published runtime, SDK and witness code | Publication graph and toolchain controls | PASS | `.evidence/final-v2/20261009T022607Z`; `.evidence/cpu-baseline/20261009T024000Z-published-replay/` |
| N2-CPU-02 | Exact SDK and setup bytes execute without undeclared mandatory CPU extensions | Source-free assembly and delivered lifecycle in a recorded CPU context | PASS | `.evidence/cpu-baseline/20261009T024000Z-published-replay/qualification.json`; original failure retained separately |
| N2-AUTH-02 | Native/C/Starlark equivalent models, owned values, source maps and generic worker arguments | `apps/compiler-sdk/c/root_test.zig` | PASS | `.evidence/author-v2/20261008T194115Z-92f15f47e115d915` |
| N2-AUTH-03 | Equivalent Zig/C/Starlark programs become executable setups | `tests/core_e2e/frontends.zig` | PASS | `.evidence/core-e2e/20261008T194101Z-12ad24aac3dd97c8` |
| N2-COMPILER-02 | common backend verifies WIT bindings and returns source diagnostics | `libs/compiler/pipeline_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-COMPILER-03 | raw tar identity differs from canonical embedded content | `libs/compiler/pipeline_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-COMPILER-04 | CLI requires explicit locked identities and rejects duplicate options | `apps/compiler/options.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-COMPILER-05 | source sidecars reject ambiguous namespaces and preserve semantic identity | `libs/compiler/pipeline_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-COMPILER-07 | profile one rejects callable imports even when a host contract matches | `libs/compiler/pipeline_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-COMPILER-08 | unused inputs have resolved types and ambiguous or forged types reject | `libs/compiler/pipeline_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-COMPILER-09 | selected resource-returning functions reject even without graph consumers | `libs/compiler/pipeline_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-COMPONENT-01 | Standard Component profile: C/Rust consumers, upstream ABI, initialization and resource budgets | `tests/component/main.zig` | PASS | `.evidence/component/20261008T194058Z-e2dc3ae7662e1b6f` |
| N2-COMPONENT-02 | process response shape is checked before consumption | `libs/component_client/root.zig` | PASS | `.evidence/component-ipc/20261008T194146Z-6a5c8105db688a16` |
| N2-CONTENT-01 | canonical tree includes modes empty directories and UTF-8 symlinks | `libs/content/content_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-CONTENT-02 | parser rejects traversal special types duplicate and corrupt entries | `libs/content/content_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-CONTENT-03 | filter remap merge and generated snapshot reject conflicts | `libs/content/content_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-CONTENT-04 | file payload streams with metadata-only allocation | `libs/content/content_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-CONTENT-05 | logical link kinds follow chains without rewriting readlink text | `libs/content/content_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-CORE-E2E-01 | Final setup files, generated toolchain content, reconfiguration, explicit update and uninstall | `tests/core_e2e/main.zig` | PASS | `.evidence/core-e2e/20261008T194101Z-12ad24aac3dd97c8` |
| N2-CORE-E2E-02 | Fresh second release initializes its declared state representation | `tests/core_e2e/main.zig` | PASS | `.evidence/core-e2e/20261008T194101Z-12ad24aac3dd97c8` |
| N2-CROSS-01 | Source-free Linux x64 assembly of PE, ELF and Mach-O without target execution or runtime relinking | `tests/core_e2e/cross_assemble.zig` | PASS | `.evidence/core-cross/20261008T152953Z` |
| N2-CROSS-02 | Exact transferred Linux-built setup bytes execute the target lifecycle | `tests/core_e2e/delivered.zig` | PASS | `.evidence/core-cross/20261008T152953Z`; contexts below |
| N2-EVAL-01 | typed projections and aggregates preserve values | `libs/evaluator/bindings.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-EVAL-02 | generated trees cannot forge paths or malformed permissions | `libs/evaluator/values.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-EVAL-03 | host plan normalization preserves additional typed downstream fields | `libs/evaluator/proposals.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-EVAL-04 | executable capture follows the verified file, not a replaced pathname | `libs/evaluator/executable.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-EVAL-05 | a reused evaluator cannot resolve a prior evaluation's generated reference | `libs/evaluator/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-IMAGE-02 | image references reject unknown versions and nonzero reserved bytes | `libs/image/image_test.zig` | PASS | `.evidence/image/20261008T194114Z-5d7adf6372481a5c` |
| N2-IMAGE-03 | Portable ad-hoc verification agrees with native macOS verification on Linux-signed bytes | `libs/image/signature.zig` | PASS | `.evidence/image/20261008T142111Z-prefix-cross` |
| N2-KERNEL-01 | two named roots install reconfigure migrate and uninstall | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-02 | optional empty desired tree clears state and preserves user-added files | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-03 | grant escalation digest mismatch and missing migration fail before activation | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-04 | unknown plan versions and foreign roots are rejected without mutation | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-05 | state cannot cross selectors or library identities | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-06 | read-only payload access is restored and source modes grant nothing | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-07 | legacy or nonempty unowned roots cannot be adopted | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-08 | confined symlink is exact or explicitly unsupported before publication | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-09 | repair restores desired bytes while retaining modified prior content | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-10 | preexisting pointer work files survive rejection | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-11 | malformed durable model migration history is rejected | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-12 | a stateless plan cannot discard capability ownership | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-13 | null private state retains version and refuses value-consuming migration | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-14 | byte ceiling rejects before CAS publication | `tests/kernel/budget_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-15 | entry ceiling includes synthesized prefix parents | `tests/kernel/budget_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-16 | target names follow the native filesystem contract | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-17 | native alias collisions reject before publication without global folding | `tests/kernel/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-18 | Windows rejects unsafe native link syntax before CAS writes | `tests/kernel/budget_test.zig` | PASS | `.evidence/native-platform/20261008T145621Z` |
| N2-KERNEL-19 | unused typed overrides fail before claiming a root | `tests/kernel/input_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-RECOVERY-01 | Real process termination at each multi-root durability boundary; repeated guest-free recovery | `tests/kernel/main.zig` | PASS | `.evidence/kernel/20261008T194243Z-6e3168f8237f15c5` |
| N2-LIB-02 | Official and independent libraries use the same typed boundary and fixed runtime | `tests/core_e2e/main.zig` | PASS | `.evidence/core-e2e/20261008T194101Z-12ad24aac3dd97c8` |
| N2-MODEL-01 | v2 normalization preserves typed binding order and graph semantics | `libs/program/model_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-MODEL-02 | invalid graph references cycles targets and authority fail | `libs/program/model_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-MODEL-03 | aggregate bindings normalize records and preserve nested dependencies | `libs/program/model_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-PRIMITIVE-01 | facts are typed observations and unsupported requests stay explicit | `libs/host_primitives/root.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-PROFILE-01 | target and primitive versions never fall back | `libs/program/profile.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-PROFILE-02 | locked metadata must describe the exact runtime publication | `libs/compiler/runtime_package.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-PROFILE-03 | Runtime-package schema 2 requires an explicit matching CPU/ABI declaration | `libs/compiler/runtime_package.zig`, compiler CLI and package schema | PASS | `.evidence/cpu-publication/20261009T020437Z/`: native/CLI tests and 13 schema/native vectors; no CPU execution claim |
| N2-RUNTIME-02 | CLI preserves typed options and rejects ambiguous arguments | `apps/runtime/arguments.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-RUNTIME-03 | metadata reads use the captured image through A-B-A source changes | `apps/runtime/product.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-SAFE-02 | Bounded product-v2, native image and content parser corpus replay | `fuzz` | PASS | `.evidence/fuzz/1791473758366-suite-fuzz-91e3d412f9f9f6f0` |
| N2-SIGNATURE-01 | code pages payload and special-slot hashes are all verified | `libs/image/signature_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-TYPES-01 | WIT host values preserve exact integer widths and reject invalid data | `libs/program/value.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-TYPES-02 | reflected WIT types validate named records and exact widths | `libs/program/wit.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-TYPES-03 | determinate defaults infer full types rather than singleton values | `libs/program/wit_inputs.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-IMAGE-04 | Native prefix identity, approved masks and old-template rejection | `image-test` | PASS | `.evidence/image/20261008T194114Z-5d7adf6372481a5c` |
| N2-KERNEL-20 | Applied product and converter rule identities remain immutable | `kernel-test` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-21 | Resolved directory links use native kind and unlink without following | `kernel-test` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-KERNEL-SCHEMA-01 | Native state/plan schema conformance and strict negative vectors | `kernel-test` | PASS | `.evidence/kernel/20261008T145940Z-schema-qualified` |
| N2-KERNEL-SCHEMA-02 | Durable encoders and decoders share the same envelope limits | `kernel-test` | PASS | `.evidence/kernel/20261008T145940Z-schema-qualified` |

## Target and permission qualification

| Target/context | Required evidence | Status | Evidence |
|---|---|---|---|
| macOS arm64, user, native, APFS | Final setup, strict signature, lifecycle, owner access and crash recovery | PASS | `.evidence/core-cross/20261008T152953Z/macos-execution.json`; `.evidence/final-v2/20261008T194056Z` |
| Linux x64 userspace under Rosetta, uid/gid 65534, ext/tmpfs | Source-free assembly and exact setup lifecycle; owner/other-user access and real kills | PASS | `.evidence/core-cross/20261008T152953Z/linux-execution.json`; `.evidence/native-platform/20261008T144729Z` |
| Windows x64 under ARM64 emulation, standard user, NTFS | Exact Linux-built setup, owner/other-user access, privilege-dependent links and recovery | PASS | `.evidence/core-cross/20261008T152953Z/windows-delivered/`; `.evidence/native-platform/20261008T145621Z` |
| Ubuntu 24.04 x64, native hosted CI | Native SDK publication and exact Linux-assembled setup lifecycle | PASS | CI `37830364529`; `.evidence/core-ci/20261008T193700Z-native-matrix-green/` |
| Windows Server 2025 x64, native hosted CI | Native SDK publication and exact Linux-assembled setup lifecycle in the runner token context | PASS | CI `37830364529`; `.evidence/core-ci/20261008T193700Z-native-matrix-green/` |
| Machine scope, other architectures, Developer ID/notarization and publisher signing | Separate profile, authority and final-byte qualification | DEFERRED | Follow-on roadmap packages |

Permission assertions must distinguish native ACL/mode inspection from effective
access by an independent identity. Unsupported symlink privilege, filesystem
semantics or ACL features must return explicit refusal before commitment. An
emulated x64 execution is recorded as such, without a physical x64 claim.

## Evidence requirements

Record source revision and dirty-tree identity, tool/runtime/library identities,
commands, exit status and final setup digests. Preserve the first failing record.
Native witness receipts include real file contents, active generation, permissions,
state and migration history. Recovery records identify each kill boundary and
show OLD or NEW across all roots after recovery and unchanged repeated recovery.

Cross-host qualification publishes only fixed inputs and tools into an isolated
Linux environment with no checkout or runtime compiler/linker. Archive/model
creation precedes that boundary. Record the mounts, executable inventory and
absence of build toolchains. Copy delivered outputs without rebuilding; compare
source/destination hashes before running each target witness. A target-side
witness can run without a checkout; its executable digest and external producer
source ledger must be retained together.

The earlier broad N2-COMPILER-01, N2-SDK-01, N2-HOST-01 and other follow-on IDs
remain scoped to their original work packages. New foundational tests do not
turn those entire packages into PASS. The detailed handoff is
[roadmap](roadmap.md).

## Recorded qualification

The latest recorded CPU publication matrix is
[CI run 37874568090](https://github.com/niobium-project/niobium/actions/runs/37874568090).
Its source head is `e2adc8a9028f93820738990166ac4399e6d4e7dc`, tested merge
`217110ca253306009e1be65500604fd0868e95f6`, and tree
`f643076998d4e6e3e694fd3bdaf3d0051168149b`. The publisher, isolated assembly
and three delivered-byte witnesses are archived under
`.evidence/cpu-baseline/20261009T024000Z-published-replay/`.
Those records cover their exact source, CPU and OS contexts, not the current dirty
cleanup tree. The paired Rosetta replay remains emulated CPU evidence, with UID/GID
0 on tmpfs; it is not an unprivileged or universal physical-CPU qualification.
First failures remain in archived evidence and Git history.

The current cleanup tree has separate package-consumption records, both based on
`a790b0374d09d4dedf892a91e66ac7f62e9e49f2` with `dirty=true`:

| Check | Result | Evidence and limit |
|---|---|---|
| `zig build sdk:c sdk:zig --cache-poison=disallowed`; extracted C consumer linked and ran; external Zig `compiler.author` dependency passed `zig build test --cache-poison=disallowed` | PASS | `.evidence/sdk-consumption/2026-10-09T12-34-01Z/metadata.json`, archive inventories and consumers; macOS arm64 native C archive and target-independent Zig source archive |
| `zig build runtime:package --cache-poison=disallowed`; extracted runtime profile and framework metadata version | PASS | `.evidence/runtime-package/2026-10-09T12-36-13Z/metadata.json`, profile and archive inventory; macOS arm64 template is 9,501,856 bytes |

These package checks do not complete additional-language SDKs, certify the current
full installer matrix or qualify machine scope and publisher signing. Runtime
publication retains the component binary policy's dependency, hardening, 30 MiB
ceiling and five-percent growth checks. `check:binary` names that aggregate.

## Independent components and shared test-system evidence

These N1 obligations retain their original independent component or test-system
scope. Their recorded PASS results refer only to the source snapshots and
execution contexts cited below; they do not qualify the current installer.

| ID | Description | Coverage | Status |
|---|---|---|---|
| N1-INV-02 | Artifact unpacking cannot write outside the staging root | zig test | PASS |
| N1-INV-04 | The helper accepts only closed ops, a matching tx/nonce, increasing ids and paths inside a managed root | zig test | PASS |
| N1-INV-05 | TUF rejects expired, rolled-back, forged, below-threshold, wrong hash/length | zig test | PASS |
| N1-AC-02 | Canonical JSON and Ed25519 signature verification | zig test | PASS |
| N1-AC-03 | Root version-chain rotation | zig test | PASS |
| N1-AC-04 | All malicious archive fixtures are rejected | zig test | PASS |
| N1-AC-11 | UiTree / DisplayList / SemanticTree snapshots are deterministic | zig test | PASS |
| N1-AC-12 | Offscreen pixel golden | zig test | PASS |
| N1-AC-13 | Tokens contrast gate | build | PASS |
| N1-AC-14 | Host PlatformContract suite | zig test | PASS |
| N1-AC-16 | Binary lint: dynamic dependency allowlist, PE flags, no RWX | build | PASS |
| N1-AC-17 | All targets cross-compile | build | PASS |
| N1-AC-20 | check / lint / check-docs all pass | build | PASS |
| N1-AC-21 | Parsers return an error instead of crashing under every allocation failure | zig test | PASS |
| N1-INV-03 | Forbidden fields in manifest/component are rejected | zig test | PASS |
| N1-INV-06 | release_sequence strictly increases; app_version may downgrade | zig test | PASS |
| N1-INV-08 | Unknown schema / too-old installer fails closed | zig test | PASS |
| N1-AC-01 | Strict manifest parsing (unknown fields, duplicate keys, limits) | zig test | PASS |
| N1-AC-09 | CLI exit codes and JSON event schema | zig test | PASS |

## Shared test-system qualification

Current shared obligations include strict saved-record validation, bounded capture,
source/binary identity, first-failure preservation, conflicting-object refusal,
report-last publication recovery, trusted CI provenance and credential isolation.
[The test-system contract](spec/test-system.md) owns their current behavior. The
current archive-key validator rejects historical pre-prefix keys; earlier provider
records do not qualify that changed validator.

Latest applicable provider evidence is
`.evidence/unit/1791410625926-tool-evidence-243ed4211bcd7745/report.json`, based on
`58407c1` with `dirty=true`. It covers native shared-file credential authentication
and real conditional publication/readback. The independent archive records
`.evidence/readback-37683496636-xw_za1ya/report.json` and
`.evidence/readback-37688502195-8ja_w7bb/report.json` retain their original fork/main
source identity and verdicts; validation did not execute saved artifacts.
These records are source-scoped evidence, not current full-suite qualification.

Trusted publication was verified by
[main publisher 37689468745](https://github.com/niobium-project/niobium/actions/runs/37689468745)
and [fork publisher 37688512199](https://github.com/niobium-project/niobium/actions/runs/37688512199),
using trusted source `879a89e`. The private Standard bucket's monthly ordinary
90-day retention policy needs renewal before September 2027 ends. Missing expiry
fails publication without altering test verdicts. Original deployment details and
retired product/simulation results remain available through Git and their archived
producer records rather than additional current documentation versions.

## Compiler follow-on obligation

| ID | Description | Coverage | Status | Completion condition |
|---|---|---|---|---|
| N2-COMPILER-01 | Locked resolution, deterministic cache, incremental builds and cancellation | compiler conformance | DEFERRED | Clean/cached equality and invalidation matrix; existing cache/lock unit tests are partial coverage only |
