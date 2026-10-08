# Acceptance plan v0.3: Standard core infrastructure

This plan owns the standard Component/product-v2 profile under
[ADR-0023](adr/0023-standard-content-and-component-contracts.md).
[Acceptance v0.2](acceptance-plan-v0.2.md) retains the earlier Core Wasm profile;
its results do not establish these new contracts. IDs retain their original scope.

Status is `PASS`, `FAIL`, `BLOCKED`, `NOT_RUN` or `DEFERRED`. Implementation,
compilation, isolated conformance and target execution are separate claims.
A target claim records OS/version, CPU/emulation, filesystem and privilege scope.

## Current gates

`zig build core-test` is a dependency of `verify`. It includes typed model and
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
| N2-AUTH-02 | Native/C/Starlark equivalent models, owned values, source maps and generic worker arguments | `apps/libcompiler/v2_test.zig` | PASS | `.evidence/author-v2/20261008T194115Z-92f15f47e115d915` |
| N2-AUTH-03 | Equivalent Zig/C/Starlark programs become executable setups | `tests/core_e2e/frontends.zig` | PASS | `.evidence/core-e2e/20261008T194101Z-12ad24aac3dd97c8` |
| N2-COMPILER-02 | common backend verifies WIT bindings and returns source diagnostics | `libs/compiler/pipeline_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-COMPILER-03 | raw tar identity differs from canonical embedded content | `libs/compiler/pipeline_test.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-COMPILER-04 | CLI requires explicit locked identities and rejects duplicate options | `apps/compiler-v2/options.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
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
| N2-RUNTIME-02 | CLI preserves typed options and rejects ambiguous arguments | `apps/runtime-v2/arguments.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
| N2-RUNTIME-03 | metadata reads use the captured image through A-B-A source changes | `apps/runtime-v2/product.zig` | PASS | `.evidence/final-v2/20261008T194056Z` |
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
[roadmap v0.3](roadmap-v0.3.md).

## Recorded source qualification

`zig build verify --cache-poison=disallowed --summary all` completed **772/772
steps**, with **157/158 reported tests passed and one Windows-only case skipped**
on macOS arm64. Evidence: `.evidence/final-v2/20261008T194056Z/result.json` and
`verify.log`. Per-suite producer records identify their source snapshot and actual
executed test/installer bytes. The Windows-specific link-input case has separate
actual Windows evidence; the local skip is not a Windows support claim.

`zig build fuzz sim -Dseeds=2000 --cache-poison=disallowed --summary all` completed
**11/11 steps**. Corpus replay is recorded in
`.evidence/fuzz/1791473758366-suite-fuzz-91e3d412f9f9f6f0`; retained transaction
simulation is recorded in `.evidence/sim/1791473737843-suite-sim-188233f828caae6a`.
This is bounded corpus replay, not a sustained fuzzing campaign.

The native runtime templates are approximately 9.0 MiB (macOS arm64), 8.7 MiB
(Linux x64) and 8.5 MiB (Windows x64). Final setup sizes additionally include their
product/library/content payload. The linter reports 68 suppressions: the two added
ones are narrowly scoped to real deadline/cancellation fault subjects in Component
client tests. No safety rule or existing regression was disabled.

The isolated Linux run at `.evidence/core-cross/20261008T152953Z` assembled twelve
PE/ELF/Mach-O images from published byte inputs. Its ledger includes mounts,
toolchain absence, inputs, source revision and final image digests; transferred
hashes match. macOS target execution is recorded in
`.evidence/core-delivered/20261008T153143Z-1720a2e70d9b585d`; Linux uid/gid 65534
execution is recorded under the cross run's `output/linux-evidence/`. Windows
standard-token execution is recorded under `windows-delivered/`; all four setup
digests match the Linux producer ledger. The initial Windows launch failed with
error 740 because installer detection required elevation. The published runtime
now embeds an `asInvoker` manifest; the same final filenames pass without elevation.
The first failure remains at `.evidence/core-cross/20261008T151143Z/windows-delivered/`.

Windows execution recorded seven private worker-copy cleanup warnings after
otherwise successful evaluations. Later same-token deletion succeeded; no access
policy or lifecycle assertion was bypassed. The outstanding cleanup qualification
is described in [runtime lifecycle](spec/runtime-lifecycle-v2.md). The initial native CI failures remain archived. The corrected native matrix
passed in run `37830364529`, including all three publishers, source-free Linux
assembly, three delivered-byte witnesses and the required aggregate gate.

PR review qualification: `.evidence/pr-review/20261008T155457Z/` preserves the
runtime-metadata version mismatch before its fix and the complete verifier after
the fix. Parser-root guidance now points to the owning lint list. Native CI fixture
fixes are recorded in `.evidence/linux-ci-fixes/20261008T160057Z/`; Component IPC
relative-path qualification is `.evidence/component-ipc/20261008T160106Z-e4339b27d21b62be/`.
ABI-specific runtime publication now includes binary dependency/interpreter and
size/growth gates under [ADR-0024](adr/0024-native-runtime-dependency-qualification.md).

## Native CI qualification

[Core v2 run 37830364529](https://github.com/niobium-project/niobium/actions/runs/37830364529)
completed `PASS` for PR head `3da1a9617c8480756b70bd64cac824288929dba4`.
The tested synthetic merge commit was `6f5ebaf0c4e96c071820b8396d795be6b097cb00`;
its tree `5a9f44fd519266fede3210fd407f00f749376fe4` equals that PR head
(the equality is recorded in `qualification.json`).

Native contexts were macOS 15.7.9 arm64, Ubuntu 24.04 x64 with glibc 2.39, and
Windows Server 2025 x64. CI proves user-scope product operations in hosted runner
contexts. It does not establish a native Windows non-administrator token claim;
the separate Windows 11 ARM64/x64-emulated standard-token record remains scoped
to that environment. CPU portability beyond each recorded host remains proposed
in [ADR-0025](adr/0025-baseline-cpu-runtime-publication.md).

Downloaded evidence is `.evidence/core-ci/20261008T193700Z-native-matrix-green/`:
`run.json`, `artifacts.json`, `qualification.json`, assembly publisher/container/
output inventories, and all three delivered-image identity and lifecycle records.
The pipeline assembled twelve images from published SDK inputs without a checkout
or runtime compiler/linker; delivered witnesses verified the archive and image
identities before executing those same bytes. The existing CI and user-site build
also completed `PASS` for the code commit.

The Windows fixes retain their first failures: explicit `ntdll` author linkage,
upstream GNU COFF weak-alias compatibility, platform Git argv and ordered CGO
build/test work. With the same GCC and archive, GNU ld 2.45 failed and 2.47 passed.
Internal Windows Starlark compilation now uses pinned Zig CC/LLD. All five Go
test bodies passed in 0.092 seconds; the longer command time was cold compilation.
The outer 300-second deadline and all test cases remain enabled.
