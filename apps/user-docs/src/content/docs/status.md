---
title: Status and platforms
description: Current Component qualification boundaries and historical results within their original scope.
---

## Current standard Component profile

[Acceptance v0.3](https://github.com/niobium-project/niobium/blob/main/docs/acceptance-plan-v0.3.md)
records actual commands, source/artifact identities and evidence for the compiler,
standard WIT libraries, content/access, native assembly and maintenance. The
foundational CLI slice passed its native publishing, isolated assembly and final-byte
matrix in [CI run 37874568090](https://github.com/niobium-project/niobium/actions/runs/37874568090).
Current interfaces remain experimental.

Niobium runtime and SDK code use versioned minimum CPU profiles. The exact
Linux SDK and setup bytes also passed in a recorded x64 emulation context lacking
SHA/SSE4a extensions. That record remains scoped to its CPU, filesystem and
privilege context; it does not qualify every physical CPU or older operating system.

Author parity, standard ABI/worker isolation and foundation tests are distinct
from final setup lifecycle, permissions, signing and crash-recovery evidence.
Compilation is not final-byte execution, and local emulated-target results do not
replace native-target CI. The recorded native environments are macOS 15.7.9 arm64,
Ubuntu 24.04 x64 and Windows Server 2025 x64. Hosted runner operations do not
establish a native Windows standard-user token claim or generic CPU portability.
Machine scope, Developer ID, notarization, Authenticode and a standard v2 UI remain
separate work packages. The recorded Windows private worker-copy cleanup limitation
also remains open.

Run `zig build test:author test:component test:core` for foundation checks and
`zig build core:e2e` for delivered-artifact scenarios. `zig build verify` is the
complete gate. Each platform's actual scope comes from its acceptance record,
not the historical tables below.

[Acceptance v0.2](https://github.com/niobium-project/niobium/blob/main/docs/acceptance-plan-v0.2.md)
retains the earlier Core Wasm/WAMR PoC. The following N1 tables preserve the
manifest/engine implementation's historical results and do not qualify the
current profile.

## Historical v1 status


Niobium 0.1 is a vertical slice that proves the model; it is not production-ready. The following records describe its historical verification.

Statuses use five values only:

| Status | Meaning |
|---|---|
| `PASS` | Verified by an automated test or build gate, with recorded evidence |
| `FAIL` | Verified and failing |
| `BLOCKED` | Cannot run yet; the reason is recorded |
| `NOT_RUN` | Can run, has not been run |
| `DEFERRED` | Deliberately out of scope for this version |

The source of truth for these historical N1 records is the repository's [acceptance plan](https://github.com/niobium-project/niobium/blob/main/docs/acceptance-plan-v0.1.md) and [development roadmap](https://github.com/niobium-project/niobium/blob/main/docs/roadmap-v0.1.md); if this page and those disagree, they are right. Current planned work is on the [Roadmap](/roadmap/).

## Historical verification environment

The following historical `PASS` entries come from `zig build verify` on a macOS arm64 host; the end-to-end suite also passes in a Debian bookworm arm64 container. At the time of this historical record, no real Windows machine or full Linux desktop had been verified.

Build targets are `x86_64-windows`, `aarch64-macos` and `x86_64-linux`, plus `aarch64-linux` for VM tests; their support tiers and reference operating systems are on [Platform support](/platforms/). All of them cross-compile and pass the binary checks, and the three shipping targets keep `setup` under 30 MiB (N1-AC-15 to N1-AC-17: `PASS`). Compiling for a platform is not the same as having verified it there.

## Historical user journeys

| ID | Journey | Status |
|---|---|---|
| N1-UJ-01 | User-scope online install from an HTTP repository; App Bootstrap is invoked | `PASS` |
| N1-UJ-02 | Administrator silent install, `install --silent --json --scope machine` | `BLOCKED` |
| N1-UJ-03 | Update to a higher `release_sequence` | `PASS` |
| N1-UJ-04 | Incident rollback: a higher sequence ships an older application version | `PASS` |
| N1-UJ-05 | Repair restores deleted or tampered files | `PASS` |
| N1-UJ-06 | Uninstall leaves the install root and integrations clean | `PASS` |
| N1-UJ-07 | Install from an offline bundle | `PASS` |
| N1-UJ-08 | Portable Run: authorization, cache, execution, cleanup | `PASS` |
| N1-UJ-09 | A C program completes check, resolve, fetch, stage and commit through the C ABI | `PASS` |
| N1-UJ-10 | The five installer window screens complete an install on macOS (manual walkthrough) | `NOT_RUN` |

N1-UJ-02 is blocked for the same reason as the real-OS smoke tests below, and additionally because the smoke tool runs user scope only so far.

## Historical guarantees

| ID | Guarantee | Status |
|---|---|---|
| N1-INV-01 | After recovery from any kill point, the active version is the old or the new one | `PASS` |
| N1-INV-02 | Unpacking an artifact cannot write outside the staging directory | `PASS` |
| N1-INV-03 | Forbidden manifest and component fields are rejected | `PASS` |
| N1-INV-04 | The elevated helper accepts only its closed operations, inside the managed root | `PASS` |
| N1-INV-05 | TUF rejects expired, rolled-back, forged, under-threshold and mismatched metadata | `PASS` |
| N1-INV-06 | `release_sequence` strictly increases; the application version may go down | `PASS` |
| N1-INV-07 | The window and the command line run the same engine and plan | `PASS` |
| N1-INV-08 | Unknown schema versions and too-old installers fail closed | `PASS` |

These run on the build host against a test platform with injected faults and against the host's real file system. They are not evidence for platforms that have not been run (below).

## Historical platform records

| Item | Status |
|---|---|
| Real-OS smoke test, Windows 11 (N1-AC-18) | `BLOCKED` |
| Real-OS smoke test, Ubuntu 24.04 arm64 (N1-AC-19) | `BLOCKED` |
| Authenticode and Apple Developer ID signing and notarization | `DEFERRED` |
| Native Wayland window backend (Linux uses X11) | `DEFERRED` |
| Screen-reader bridges (UI Automation, NSAccessibility, AT-SPI) | `DEFERRED` |
| Native folder picker on Linux | `DEFERRED` |

The real-OS smoke tests are blocked because the test virtual machines were not running when the suite last ran. What each platform is committed to, and which test lanes are still missing, is on [Platform support](/platforms/).

## Historical deferred features

| Item | Status |
|---|---|
| Embedded updates for Electron hosts (`distribution.node`) | `DEFERRED` |
| Protocol handlers, autostart entries and environment variables as capabilities | `DEFERRED` |

## Historical gaps without an acceptance entry

- `nbpack` cannot rotate root or online keys yet; clients already verify rotated roots ([Sign and manage keys](/guides/sign-and-keys/#rotate-or-recover-keys)).
- There is no published security policy or private reporting channel ([Security](/security/#report-a-vulnerability)).
- The build API carries no compatibility promise in 0.1: pin a commit. The `setup` exit codes and JSON event schema are declared a compatibility contract ([exit codes](/reference/exit-codes/)), and the C ABI changes only by appending to its versioned function table.
