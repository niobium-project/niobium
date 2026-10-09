---
title: Platform support
description: Which platforms Niobium targets, what each support tier commits to, and what comes next.
---

This page records platform tier obligations and remaining qualification work. Current Component evidence and retained v1 records have separate scopes on [Status and platforms](/status/).

Niobium sorts the platforms it builds for into three tiers. A tier states what the project commits to on that platform; whether the commitment is met today is recorded on [Status and platforms](/status/), the only page that reports results.

The list is short on purpose. Niobium is maintained by one person in spare time, with no company resources behind it ([About the project](/about/)), and every Tier 1 platform costs build, test and release time on every change.

## Tiers

| Tier | Built on every change | Tested on a real OS before a release | Can block a release | Fixes |
|---|---|---|---|---|
| Tier 1 | Yes | Required | Yes | First priority |
| Tier 2 | Yes | Best effort | No | When time allows |
| Tier 3 | No | No | No | Only with a volunteer owner |

- **Built on every change** means the target is cross-compiled in ReleaseSafe and its binaries pass the binary lint (allowed dynamic libraries, PE flags, no writable and executable memory). Component runtime publication enforces its native ABI profile, the 30 MiB runtime ceiling and the growth bound; product payload capacity is separate ([ADR-0024](https://github.com/niobium-project/niobium/blob/main/docs/adr/0024-native-runtime-dependency-qualification.md)).
- **Tested on a real OS** means the platform contract suite, the end-to-end install, update, repair and uninstall scenarios and a smoke run on the reference OS. For a Tier 1 platform, a known failure blocks the release; a test that could not run is reported in the release notes as `BLOCKED` or `NOT_RUN`, never as passed.
- **Tier 3** platforms are candidates. Nothing is built for them by default, and nothing about them is promised.

## Current platforms

| Target | Tier | Reference OS | Notes |
|---|---|---|---|
| `aarch64-macos` | 1 | macOS on Apple silicon | The minimum macOS version is not pinned yet |
| `x86_64-windows` | 1 | Windows 11 (x64) | |
| `x86_64-linux` | 1 | Ubuntu 24.04 LTS | The measured Component GNU runtime requires glibc 2.36 and its declared loader; other distributions are not qualified |
| `aarch64-linux` | 2 | Ubuntu 24.04 (ARM64) | Built and linted, used for VM smoke runs; not yet a shipping target, so the size budget does not apply |

Results for each target are on [Status and platforms](/status/). Native dependencies are qualified per OS and ABI under [ADR-0024](https://github.com/niobium-project/niobium/blob/main/docs/adr/0024-native-runtime-dependency-qualification.md); GNU and static musl are separate profiles. Published runtime and SDK CPU baselines follow [ADR-0025](https://github.com/niobium-project/niobium/blob/main/docs/adr/0025-baseline-cpu-runtime-publication.md). A baseline setting or successful cross-build does not qualify every CPU or older operating system.

## Roadmap

This section covers platforms only. Planned features are on the [Roadmap](/roadmap/).

### Before the first Tier 1 release

Each Tier 1 platform still has a gap between its commitment and its test lanes:

- **`x86_64-linux`:** native hosted Ubuntu 24.04 x64 CI is recorded for the current Component profile. Older distributions and generic physical-CPU portability remain outside that evidence.
- **`x86_64-windows`:** native hosted CI runs on Windows Server 2025 x64. That runner context does not qualify the Windows 11 x64 reference OS or a native standard-user token. The Windows 11 ARM64/x64-emulated standard-user record keeps its separate scope.
- **All platforms:** current qualification covers user scope; machine scope and the standard v2 UI remain separate work packages.
- **`aarch64-macos`:** native hosted macOS 15.7.9 arm64 CI is recorded. The minimum supported macOS version remains unpinned; the retained v1 graphical walkthrough remains a historical `NOT_RUN` record.

### Candidates

| Candidate | Tier | What it needs |
|---|---|---|
| `aarch64-windows` | 3 | A build target and binary-lint entry, and a real-OS lane on Windows 11 for ARM64 |
| Kylin and UOS, x86_64 and aarch64 | 3 | A real-OS lane per distribution that checks the native ABI, loader, CPU prerequisites and desktop integrations (`.desktop` entries, MIME packages, systemd units, XDG directories); static musl evidence does not qualify a GNU runtime |

### Not planned

- **A native Wayland backend for the retained v1 window.** On Wayland sessions that window runs through XWayland ([ADR-0010](https://github.com/niobium-project/niobium/blob/main/docs/adr/0010-x11-now-wayland-deferred.md)). The current Component runtime is headless; the standard v2 UI has separate implementation and qualification work.

## Moving between tiers

A platform moves up a tier when it has all of the following:

- a repeatable test lane on the reference OS that produces recorded evidence;
- a named reference OS version;
- a maintainer with the time to keep that lane running.

Moving into Tier 1 also needs a recorded decision, because it adds work to every release. A Tier 1 platform whose real-OS lane stays unavailable for two releases in a row moves down to Tier 2.

Ports to a Tier 3 candidate are welcome when they come with someone who will keep the test lane running, and when they add no work to the Tier 1 platforms. The policy itself is recorded in [ADR-0014](https://github.com/niobium-project/niobium/blob/main/docs/adr/0014-tier-based-platform-support.md).
