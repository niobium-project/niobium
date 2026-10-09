---
title: Compiled product and desired state
description: How build-time author code produces a fixed typed model and runtime calls produce desired installation resources.
---

A Niobium product starts as build-time code. The author constructs a typed model; fixed capability libraries later use that model, installation inputs, and observations to propose desired resources.

The [DSL tutorial](/tutorial/) follows this flow with a Starlark product. The current Component-v2 profile uses command-line operation and user-scope roots. Execution qualification is recorded separately on [Status and platforms](/status/).

## The compiled model

Native Zig, the authoring C API, and Starlark construct the same product model. Author variables, functions, conditions, and loops execute during the build. The emitted JSON is compiler output consumed by the shared compiler pipeline.

The model fixes the product identity and release sequence, typed inputs, content identities, logical roots, grants, observations, and capability calls. Each call selects an exact library implementation and exported WIT function. WIT is the WebAssembly Component interface language that defines parameter and result types.

The compiler checks those types and the selected runtime profile before packaging a complete precompiled runtime. The delivered installer contains the model and fixed libraries; installation does not execute the author source.

## Desired resources at installation time

The runtime resolves typed input values and declared read-only observations, then evaluates the compiled call graph. A plan-producing call returns desired containers with an authorized root, grant, relative prefix, and explicit file and directory access policies.

The host checks content identities, paths, ownership, access ceilings, conflicts, and budgets. It freezes the accepted content and native resource inventory before executing a [transaction](/concepts/transactions/). A library failure aborts evaluation; it cannot be treated as a successful empty plan.

For example, the tutorial binds `enabled` to the files library's request. Reconfiguration with `enabled=false` produces an empty desired content set, removing the previously published file while retaining the installation state.

## Product policy and paths

The author and libraries own selection and layout policy. The product declares logical root IDs; an invocation binds them to absolute directories. The host validates that mapping and rejects incompatible ownership or unsafe root relationships.

The tutorial declares `application` and binds it with `--root application=<absolute-directory>`. It requests the `hello` prefix within that root. No framework-selected product directory or fixed component-selection schema is required for this profile.

Product model versions and per-call state versions have separate compatibility rules. Their changes require explicit applicable upgrade or migration declarations. See the [compiled product contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/program-image.md) and [migration contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/migration.md).
