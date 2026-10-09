---
title: Niobium
description: An installation and distribution DSL with an AOT compiler and precompiled native runtime.
---

Niobium lets product teams program their installer model through language SDKs or Starlark. Its compiler validates capability contracts, fixes library and artifact identities, and packages a complete precompiled runtime into a product setup.

The runtime binds user choices and machine facts, evaluates fixed Wasm capability libraries, and applies a durable host plan. Official libraries and product libraries use the same checked interface. Product policies such as optional components, SDK coexistence and upgrade paths belong to libraries and presets.

## Authoring and execution

1. Build a product model with the authoring SDK. Functions, loops and project composition use the source language.
2. Bind library implementations and artifacts at build time. The compiler validates their contracts and packages the runtime without relinking it.
3. Distribute the final setup after any signing required by its platform profile. Runtime host primitives control machine effects, state ownership and recovery.

Author source runs only at build time. Wasm libraries receive bounded typed inputs; the host validates their proposed effects. Recovery replays frozen host operations without reevaluating the author program or library.

## Current scope

The experimental current profile uses standard WIT/Component contracts,
Wasmtime/Pulley, canonical POSIX pax content and explicit portable access policy.
Native Zig, C and Starlark construct the same model. The compiler resolves complete
input types and source diagnostics, fixes dependencies and assembles a precompiled
runtime without product-specific linking.

The CLI/user-scope foundation has local qualification slices. PE/ELF/Mach-O
assembly and local native or emulated execution are recorded separately; they do
not establish native Windows/Linux CI, machine scope or publisher authentication.
Check [Status and platforms](/status/) for the current evidence boundary.

Use the [authoring guide](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring-v2.md),
[Component SDK](https://github.com/niobium-project/niobium/blob/main/docs/development/component-library-sdk.md)
and [cross-host build guide](https://github.com/niobium-project/niobium/blob/main/docs/development/cross-host-builds.md).
The [roadmap](/roadmap/) and maintainer
[documentation index](https://github.com/niobium-project/niobium/blob/main/docs/README.md)
separate the foundation from product presets, complete language SDKs and further
platform qualification.

Existing [tutorials](/start/) and manifest/`nbpack` references describe the retained
implementation. Its 1 MiB carrier, ASCII resource names and WAMR ABI are not the
current Component/content contracts. Its acceptance results retain their original
scope. The [glossary](/reference/glossary/) defines the shared domain terms.

Project background and maintenance expectations are on [About the project](/about/).
