# Acceptance plan v0.2

N2 records evidence for the DSL/AOT architecture in [ADR-0022](adr/0022-installer-dsl-and-aot-toolchain.md). N1 remains in the [historical acceptance plan](acceptance-plan-v0.1.md) and cannot establish N2 results.

Status uses only `PASS`, `FAIL`, `BLOCKED`, `NOT_RUN`, `DEFERRED`. A row is PASS only when every required scenario ran on the stated target. A compiler result or an agent review alone does not meet an end-to-end row.

## Executable baseline

The designated target is macOS arm64, user scope, CLI, ad-hoc signed single-file setup. The program image has a 1 MiB ceiling. These rows require `zig build aot-e2e` and its lower-level checks. `zig build aot` produces tools and runtime; it is not an acceptance result.

| ID | Description | Coverage | Status | Evidence |
|---|---|---|---|---|
| N2-AUTH-01 | Zig, C and Starlark produce equivalent normalized models; bindings and C ownership are preserved | aot-e2e | PASS | `.evidence/aot/20261008T032800Z-b55200b0a349f66c` |
| N2-AOT-01 | Two products use one precompiled runtime with no runtime relink or product-stage source access | aot-e2e | PASS | `.evidence/aot/20261008T032800Z-b55200b0a349f66c` |
| N2-LIB-01 | Official and independent Wasm libraries execute through the same ABI; actual input/facts affect resources | aot-e2e | PASS | `.evidence/aot/20261008T032800Z-b55200b0a349f66c` |
| N2-SAFE-01 | Invalid programs, images and guest behavior fail within budgets before machine effects | aot-e2e | PASS | `.evidence/pr-review/20261008T032747Z/1.log (guest, parser and ownership checks); .evidence/aot/20261008T032800Z-b55200b0a349f66c` |
| N2-LIFE-01 | Packaged products install, reconfigure, update, report state and uninstall real owned files | aot-e2e | PASS | `.evidence/aot/20261008T032800Z-b55200b0a349f66c` |
| N2-MIG-01 | Explicit product and library-state 1-to-2 migration commits with resources; missing paths refuse | aot-e2e | PASS | `.evidence/aot/20261008T032800Z-b55200b0a349f66c` |
| N2-REC-01 | Real process kills recover complete OLD or NEW using frozen host plans without guest reevaluation | aot-e2e | PASS | `.evidence/aot/20261008T032800Z-b55200b0a349f66c` |
| N2-IMAGE-01 | Final setup preserves template code, runs after signing, verifies signature and rejects tampering/capacity errors | aot-e2e | PASS | `.evidence/aot/20261008T032800Z-b55200b0a349f66c` |

## Required scenarios

| ID | Positive scenarios | Negative and failure scenarios | Observable assertion |
|---|---|---|---|
| N2-AUTH-01 | Functions, loops, conditionals and module composition; identical Zig/C/Starlark program bytes | Invalid references and targets, duplicate IDs, non-UTF-8 defaults, C null/length and ownership errors | Compare canonical bytes and exact error category; preserve binding order |
| N2-AOT-01 | Isolated product assembly with published tools, template, author outputs and libraries only | Missing library/runtime, incompatible ABI and assembly capacity | Record template identity and code-section digests; no compiler/linker for runtime in trace |
| N2-LIB-01 | External library uses input, OS, architecture and existing state | Missing export/library, digest mismatch and invalid binding | Compare actual deployed bytes after changing guest code/input with same template |
| N2-SAFE-01 | Valid maximum-bound inputs remain usable | Unknown imports/WASI, start/implicit init, forged handles, pointer overflow, OOB, duplicate emit, infinite loop, memory/output/host-call limits | Bounded failure, unchanged active files/state, no ambient host access |
| N2-LIFE-01 | Install and repeat, changed input apply, higher release update, status, uninstall | Foreign owner on apply/uninstall, non-UTF-8 runtime inputs, nonempty unclaimed root, generation collision, symlink escape, corrupt state and concurrent transaction | Real filesystem contents, current generation and persisted state agree; unregistered files survive cleanup |
| N2-MIG-01 | Explicit model and state transition; migrated state feeds planning | Missing/ambiguous path, changed library identity, guest converter failure, unknown stored version | Version and resources move together; rejected transition leaves previous state |
| N2-REC-01 | Kill after plan persistence, staging, activation and commit; recover twice | Missing frozen bytes, unknown plan schema and corrupted old generation | OLD or NEW only; no partial state; guest-free recovery; corrupted old state refuses before mutation |
| N2-IMAGE-01 | Two signed setups from one immutable template | Corrupt length/digest/padding, malformed section, over-capacity payload, post-sign tampering | Native execution and strict signature verification on the same final bytes |

Lower-level unit tests should cite their N2 row. They cover parser, budget and ownership cases that are expensive to diagnose through a full setup. End-to-end evidence must still include the complete product path.

## Follow-on qualification

These IDs are reserved for the work packages in [roadmap-v0.2](roadmap-v0.2.md). Their detailed test vectors live with the owning contract; implementation cannot turn a deferred package into an implicit part of the PoC claim.

| ID | Description | Coverage | Status | Completion condition |
|---|---|---|---|---|
| N2-COMPILER-01 | Locked resolution, deterministic cache, incremental builds and cancellation | compiler conformance | DEFERRED | Clean/cached equality and invalidation matrix |
| N2-SDK-01 | Python, TypeScript, Go and Rust author SDK packages | frontend conformance | DEFERRED | Per-language package, ownership and native-equivalent setup tests |
| N2-WSDK-01 | Library packages, generation tools and conformance runner | library conformance | DEFERRED | Independent consumer across generated bindings and production host |
| N2-HOST-01 | Additional primitives and standard libraries | conformance and real OS | DEFERRED | Per-operation authority, ownership, crash and platform/scope matrix |
| N2-PRESET-01 | Components, workloads and SDK coexistence policies | product scenarios | DEFERRED | Different policies use the same kernel without new global enums |
| N2-COMPAT-01 | Applied migration history and framework format compatibility | migration conformance | DEFERRED | Rule identity/digest checks and previous-format fixtures |
| N2-BRIDGE-01 | Explicit bridge releases and multi-leg upgrade authorization | distribution e2e | DEFERRED | Every leg authorized, acquired and resumed without implicit paths |
| N2-DIST-01 | Authenticated sources, cache, channels and publishing libraries | distribution e2e | DEFERRED | Online/offline authorization and final artifact identity |
| N2-NATIVE-01 | Large carriers, PE/ELF and publisher signing | native image/real OS | DEFERRED | Final signed bytes run on each declared platform |
| N2-UI-01 | Standard UI and embedded lifecycle interfaces | UI and embedding e2e | DEFERRED | CLI-equivalent semantics, cancellation and accessibility |
| N2-PLATFORM-01 | OS, architecture and scope qualification | real OS | DEFERRED | One evidence record per claimed combination |

## Evidence and gates

`zig build verify` includes the N2 native lane on its macOS arm64 target and retains legacy regression gates. Other hosts report the native lane as NOT_RUN; cross-compilation cannot establish this lane. Platform-specific absence must remain visible in summaries.

Each `.evidence/<suite>/<UTC>/` record includes command, target, start/end time, exit code, source revision and dirty-tree identity. Include final executable, template, program, library and asset digests. Preserve process logs and filesystem/state observations, including the first failing case.

AOT runs create `metadata.json` before source capture and argument validation.
It records the suite argv, native target, UTC start/end milliseconds, exit code,
result and failure name. Git revision, dirty status and a sorted SHA-256 inventory
of tracked/nonignored working-tree files identify the source snapshot; deleted
files and symlink targets are explicit. The combined source identity and executed
suite binary digest bind those records. Capture uses fixed file/count/byte and
subprocess limits. Interrupted runs remain NOT_RUN; caught setup or execution
failures save FAIL. These local producer records do not replace trusted CI
provenance under the test-system contract.

Isolation evidence records exactly which artifacts entered product assembly and which tools ran. Recovery evidence identifies each kill point and both the pre-recovery and recovered state. A PASS entry names its actual evidence directory; placeholder paths and unexecuted commands do not qualify.

The `verify` result and individual N2 results are separate: a failed legacy gate does not erase a successful N2 run, and a successful legacy gate cannot fill a missing N2 row. Report both, including all unrun targets.

## Recorded qualification

The macOS arm64 user-scope profile completed the following commands on the dirty
implementation tree identified by `.evidence/realign-validation/20261008T015439Z/result.json`.
Compiler caches were explicitly redirected to temporary directories; their exact
settings and source-file digests are part of that record.

| Command | Result | Evidence |
|---|---|---|
| `zig build verify --cache-poison=disallowed --summary all` | PASS: 544 build steps; fresh guest, runtime and schema conformance plus cached regression results | `.evidence/realign-validation/20261008T015439Z` |
| `zig build fuzz --cache-poison=disallowed --summary all` | PASS: five corpus-replay tests, including compiled program/image/Wasm profile parsing | `.evidence/realign-validation/20261008T014952Z/1.log` |
| `zig build sim -Dseeds=2000 --cache-poison=disallowed --summary all` | PASS: retained transaction simulation; does not substitute for N2 native recovery | `.evidence/realign-validation/20261008T014952Z/2.log` |
| Starlark authoring, two signed releases, install/apply/status/uninstall | PASS: independently reproduced documented workflow | `.evidence/aot-quickstart/20261008T014458Z` |

That `verify` run executed nine real-interpreter conformance tests, ten native
runtime tests and two schema/type conformance tests. Its AOT suite also executed
real process termination, guest-free recovery and denied-source/toolchain
assembly controls. Pure tests may be reused from Zig's content-addressed cache;
the log distinguishes cached and executed results.

The precompiled runtime is 2,071,584 bytes, including its 1 MiB product slot. Its
binary and size gates are independent of the retained v1 setup budgets. No new
lint suppression was added; the repository count is 66. The reviewed complexity
baseline includes the new modules and the expanded graph/document checks.

This record does not qualify publisher signing/notarization, machine scope,
Windows/Linux runtime execution, large product images, Unicode resource names,
or the deferred language SDK packages. Ownership bookkeeping may remain after
uninstall, and retained unregistered files can cause an explicit generation
collision rather than being deleted.

## Integrated source qualification

The source snapshot in `.evidence/pr-validation/20261008T020715Z/result.json`
includes the current main-branch test and evidence infrastructure. All three
recorded commands returned zero: `verify` completed 548/548 build steps, `fuzz`
completed corpus replay, and `sim -Dseeds=2000` completed the retained simulation.
The corresponding N2 run is `.evidence/aot/20261008T020918Z`.

The same tree's user-site build produced 61 pages with valid internal links;
its log is `.evidence/pr-validation/20261008T020715Z/site.log`. Only the AGENTS
wording about shared test-system evidence and this acceptance record changed
after the source snapshot; documentation checks were repeated on those edits.

## Boundary regression qualification

Commit `54dd3f310898ce794b6de541b0007366df02c892` completed `verify` (550/550
build steps), `fuzz` corpus replay and `sim -Dseeds=2000`. Commands, exit codes
and logs are in `.evidence/pr-review/20261008T032747Z`. Its N2 evidence is
`.evidence/aot/20261008T032800Z-b55200b0a349f66c`, with a clean source revision,
716 independently checked source-file hashes and a matching executed-binary
digest. The companion deliberate argument failure saved `FAIL`, `Usage` and
exit code 1; `provenance-check.json` in the review evidence records both checks.

The regressions cover product-bound uninstall, capability-state library identity,
UTF-8 defaults/overrides/inherited state/root paths, valid Unicode roundtrips and
failure-path evidence. The acceptance-record edit was followed by documentation
and commit checks; executable sources are unchanged from the qualified commit.
