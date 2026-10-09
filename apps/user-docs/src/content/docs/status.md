---
title: Status and platforms
description: Current Component qualification boundaries and historical results within their original scope.
---

## Current standard Component profile

[Acceptance](https://github.com/niobium-project/niobium/blob/main/docs/acceptance-plan.md)
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
and remain scoped to the recorded source tree.
