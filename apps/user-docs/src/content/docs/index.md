---
title: Niobium
description: An installation and distribution DSL with an AOT compiler and precompiled native runtime.
---

**Early draft: Niobium is not usable yet and does not accept external contributions.**
Framework APIs, formats, persistent state and tools have no compatibility guarantee.
Breaking changes may happen at any time. Product upgrade recognition, explicit
migration, incompatible-state refusal and transactional recovery remain required.

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

The CLI/user-scope foundation has recorded native hosted CI and local qualification
slices. PE/ELF/Mach-O assembly and target execution have separate records. Native CI
qualifies its recorded runner contexts; machine scope and publisher authentication
remain separate work. Check [Status and platforms](/status/) for the evidence boundary.

Start with the [DSL tutorial](/tutorial/) to build, install and update a small
Starlark product, then learn how to write and compile its model.
For SDK details, use the [authoring guide](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring.md),
[Component SDK](https://github.com/niobium-project/niobium/blob/main/docs/development/component-library-sdk.md)
and [cross-host build guide](https://github.com/niobium-project/niobium/blob/main/docs/development/cross-host-builds.md).
The [roadmap](/roadmap/) and maintainer
[documentation index](https://github.com/niobium-project/niobium/blob/main/docs/README.md)
separate the foundation from product presets, complete language SDKs and further
platform qualification.

The [glossary](/reference/glossary/) defines current domain terms.

Project background and maintenance expectations are on [About the project](/about/).
