---
title: Roadmap
description: The standard-content/WIT foundation and parallel product work.
---

Niobium is an installation/distribution DSL with an AOT compiler, precompiled
runtime and standard WIT capability contracts. 🚧 marks current delivery, 🔜
parallel work after the baseline, and 🗓️ later qualification. Priority is separate
from the evidence on [Status and platforms](/status/).

| Status | Feature |
|---|---|
| 🚧 | Programmable authoring and the AOT compiler |
| 🚧 | Precompiled runtime and fixed Wasm capability libraries |
| 🚧 | Standard content, access and cross-host native assembly |
| 🚧 | Transactional deployment and explicit state migration |
| 🔜 | Incremental compiler tooling, SDK packaging and additional host primitives |
| 🔜 | Python, TypeScript, Go and Rust author SDKs |
| 🔜 | Component, SDK and toolchain presets |
| 🔜 | Distribution, trust and channels as libraries |
| 🔜 | Online, offline-file and SFX product profiles |
| 🗓️ | Publisher signing and notarization qualification |
| 🗓️ | Standard UI, embedded maintenance and accessibility |
| 🗓️ | Native-platform CI and machine-scope qualification |

Current work establishes shared typed authoring, compiler binding/cache/diagnostics,
standard Component execution, content/access contracts and recoverable native
maintenance. The official files library and independent generated-content consumer
use the same contract. A design baseline and passing local slices do not establish
completion of every product feature or platform.

Optional modules, workloads, SDK coexistence and missing-prerequisite handling
belong to product libraries and presets. Detection does not adopt shared resources.
Native mechanisms remain bounded and authorized; adding a Wasm library does not
add an OS primitive or arbitrary process authority.

The [work packages](https://github.com/niobium-project/niobium/blob/main/docs/roadmap-v0.3.md),
[feature ownership catalog](https://github.com/niobium-project/niobium/blob/main/docs/feature-coverage.md)
and [product journeys](https://github.com/niobium-project/niobium/blob/main/docs/design/product-journeys.md)
provide interfaces, dependencies, negative vectors and acceptance responsibilities.

Online/offline distribution, channels, Portable Run and embedded updates in the
retained implementations require current-contract integration and new evidence.
[Delivery milestones](https://github.com/niobium-project/niobium/blob/main/docs/adr/0020-distribution-delivery-milestones.md)
and the [distribution backlog](https://github.com/niobium-project/niobium/blob/main/docs/development/distribution-backlog.md)
keep their original scope. A single-file Component setup does not by itself qualify
all online/offline/SFX policies, publisher signing or native application metadata.

[Platform support](/platforms/) retains the project's tier obligations. Local
emulated runs cannot replace native-target CI; machine scope and the standard v2
UI remain separate qualification work.
