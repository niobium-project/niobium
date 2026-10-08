# Architecture overview

The target architecture is defined by [ADR-0022](../adr/0022-installer-dsl-and-aot-toolchain.md). The repository contains both the new compiler/runtime slice and the legacy engine. This page identifies their owners; [N2 acceptance](../acceptance-plan-v0.2.md) records which behavior has actually run.

## Compiler and runtime

```text
native Zig/C author API       Starlark worker
          |                       |
          +-------- compiler -----+
                       |
                program + bindings
                       |
        precompiled runtime + fixed Wasm libraries
                       |
                 image assembly
                       |
                signed product setup
                       |
       runtime -> Wasm host -> frozen resource plan
                       |
             host transaction/recovery
```

`libs/program` owns shared model validation, normalization and the image format. `libs/compiler` consumes that model; `apps/compiler` and `apps/libcompiler` expose build-time entrypoints. The Starlark worker lives under `apps/starlark` and calls the authoring C ABI.

`libs/wasm_profile` checks the permitted module profile. `libs/wasm_host` executes fixed libraries through WAMR and copies their proposed outputs. `libs/runtime` owns binding, installed state and durable host execution; `apps/runtime` assembles the native process.

The carrier holds product bytes in a reserved Mach-O section. Product assembly copies a complete runtime template and leaves its executable code sections intact. Final signing changes output metadata. The input template, normalized program, libraries and final setup have distinct digests.

Guest evaluation computes desired resources before mutation. Recovery uses frozen host operations and durable content; it does not repeat guest or author evaluation. Normative transitions are in [runtime-lifecycle-v1](../spec/runtime-lifecycle-v1.md).

## Retained implementation

The existing `apps/setup`, `apps/nbpack` and `apps/libdistribution` use `libs/engine`. Its pipeline is Discover, Validate, Resolve, Plan, Prepare, Execute, Commit, Bootstrap, Verify and Finalize. Manifest/component v1, TUF, archive, platform and UI behavior remain available for regression and selective reuse.

`libs/ui/core` and `libs/ui/kit` remain independent of engine/platform. The existing screens use contracts and the shared renderer. A new UI adapter must consume runtime state and inputs without receiving mutation authority.

The [module disposition table](module-boundaries.md) identifies which behavior belongs in kernel, host primitives or libraries. Porting an existing module requires N2 evidence at the new boundary; historical N1 results retain their original meaning.

## Engineering designs

[Compiler engineering](../design/compiler-engineering.md), [Wasm library SDK](../design/wasm-library-sdk.md), and [host primitives/stdlib](../design/host-primitives-and-stdlib.md) define work beyond the executable PoC. The [roadmap](../roadmap-v0.2.md) supplies independent work packages and integration dependencies.
