# Acceptance and evidence

## Status words

Use only `PASS`, `FAIL`, `BLOCKED`, `NOT_RUN`, `DEFERRED`. `PASS` must satisfy all of the following:

1. At least one test name starts with the acceptance ID;
2. That test actually ran and passed in this `zig build verify` (or the designated lane);
3. The evidence path is written into the corresponding row of `docs/acceptance-plan-v0.2.md` for N2; historical N1 rows retain their original evidence.

## ID families

N2 IDs and scenario definitions are owned by [acceptance-plan-v0.2](../../../../docs/acceptance-plan-v0.2.md). `aot-e2e` provides the native product lane; `aot-test` provides contract/host checks. The following N1 families apply only to retained regressions.

| Prefix | Meaning | Main lane |
|---|---|---|
| `N1-UJ-xx` | User journeys (install, update, repair, uninstall, offline, Portable Run) | e2e |
| `N1-INV-xx` | Invariants (OLD-or-NEW, no writes outside staging, TUF rollback rejection...) | test, sim |
| `N1-AC-xx` | Architecture acceptance (size, dependencies, ABI, UI golden, platform contract...) | check, cross, golden, conformance |

## Case shape

| Part | States |
|---|---|
| Given | Root, active pointer, manifest, and the fault or kill point |
| When | The operation (install, update, repair, uninstall, Portable Run) |
| Then | OLD or NEW, the exit code, and the journal records |
| Must not | Writes outside staging, MIXED, ops outside the closed `ipc-v1` set |
| Recover | How the user continues: rerun, repair, or the reported error |

Write the cases the risk calls for, not five per helper. A lower lane never upgrades an L5 row: VirtualPlatform or container results do not make `vm-smoke` PASS, and a missing VM is not a reason to change the architecture. First-failure retention is in [testing-lanes.md](../../../../docs/development/testing-lanes.md#evidence).

## Evidence directory

Catalog suites use `.evidence/<suite>/<execution>/report.json` and bounded attachments under [test-system-v1](../../../../docs/spec/test-system-v1.md). PoC and retained non-catalog lanes keep their explicitly documented layouts. Reports identify the command, exit code, time, source revision and artifact hashes. The evidence directory is not committed; acceptance records its location and verdict. Publication is governed by ADR-0021 and does not rerun tests.

## How to write BLOCKED

State the blocking condition and the part that was executed, for example: "vm-smoke: Windows 11 VM is suspended, `prlctl resume` failed (verbatim error); Linux ARM64 already PASS".
