---
title: Niobium
description: An installation and distribution DSL with an AOT compiler and precompiled native runtime.
---

Niobium lets product teams program their installer model through language SDKs or Starlark. Its compiler validates capability contracts, fixes library and artifact identities, and packages a complete precompiled runtime into a product setup.

The runtime binds user choices and machine facts, evaluates fixed Wasm capability libraries, and applies a durable host plan. Official libraries and product libraries use the same checked interface. Product policies such as optional components, SDK coexistence and upgrade paths belong to libraries and presets.

## Authoring and execution

1. Build a product model with the authoring SDK. Functions, loops and project composition use the source language.
2. Bind library implementations and artifacts at build time. The compiler validates their contracts and packages the runtime without relinking it.
3. Distribute the final signed setup. Runtime host primitives control machine effects, state ownership and recovery.

Author source runs only at build time. Wasm libraries receive explicit bounded inputs and host authority. Recovery replays frozen host operations without reevaluating the author program or library.

## Current scope

The executable baseline targets macOS arm64, user scope and CLI, with a bounded single-file carrier. New interfaces remain pre-release. Check [Status and platforms](/status/) for evidence before relying on a behavior.

The [roadmap](/roadmap/) separates this baseline from parallel work on SDKs, libraries, distribution and platforms. Maintainer specifications and detailed designs are indexed in the repository's [documentation](https://github.com/niobium-project/niobium/blob/main/docs/README.md).

Existing [tutorials](/start/) and manifest/`nbpack` references are retained for the legacy implementation. Their N1 results do not establish the new compiler/runtime boundary. The [new glossary](/reference/glossary/) defines current terms.

Project background and maintenance expectations are on [About the project](/about/).
