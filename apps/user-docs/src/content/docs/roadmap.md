---
title: Roadmap
description: The DSL/AOT baseline and subsequent parallel implementation work.
---

The architecture is an installation/distribution DSL, an AOT compiler, a precompiled runtime and contract-based capability libraries. 🚧 marks current delivery, 🔜 parallel implementation after the baseline, and 🗓️ later qualification. Priority is separate from execution evidence on [Status and platforms](/status/).

| Status | Feature |
|---|---|
| 🚧 | Programmable authoring and the AOT compiler |
| 🚧 | Precompiled runtime and fixed Wasm capability libraries |
| 🚧 | Transactional deployment and explicit state migration |
| 🔜 | Compiler caching, library SDK and additional host primitives |
| 🔜 | Python, TypeScript, Go and Rust author SDKs |
| 🔜 | Component, SDK and toolchain presets |
| 🔜 | Distribution, trust and channels as libraries |
| 🔜 | Online, offline-file and SFX delivery |
| 🗓️ | Large native images and publisher signing |
| 🗓️ | Standard UI, embedded maintenance and accessibility |
| 🗓️ | Windows/Linux and machine-scope qualification |

Current delivery includes detailed designs for compiler engineering, the Wasm library SDK, host primitives and stdlib. The PoC connects three authoring entrypoints, two products, an independent library, migration and recovery. A completed design does not imply every engineering feature is implemented.

Products extend behavior through capability libraries. Machine effects still require corresponding host authority and transactional operations. Runtime provides no arbitrary shell or ambient authority. Single-file setup is part of the current carrier; larger payloads and publisher signing qualify separately.

The retained N1 implementations of online/offline installation, channels, Portable Run and embedded updates provide reusable foundations. They need new contract integration and N2 evidence before becoming new-architecture features.

The maintainer [work packages and dependencies](https://github.com/niobium-project/niobium/blob/main/docs/roadmap-v0.2.md) include acceptance by package. Platform obligations are on [Platform support](/platforms/); native Wayland remains outside the current plan.

The [delivery milestones](https://github.com/niobium-project/niobium/blob/main/docs/adr/0020-distribution-delivery-milestones.md)
cover an online installer, a complete offline file opened or unpacked before
installation, and an SFX that starts installation without a separate unpacking
step. The [distribution backlog](https://github.com/niobium-project/niobium/blob/main/docs/development/distribution-backlog.md)
retains signing, scan, resource-budget, offline-validity and maintainer-lifetime
work. The bounded macOS PoC does not qualify these complete release forms.
