# Compiler and frontends v2

- **Status:** Normative v2 contract; implementation and evidence have separate N2 entries.
- **Decision:** [ADR-0023](../adr/0023-standard-content-and-component-contracts.md).
- **Owners:** `libs/compiler`, `apps/compiler-v2`, language adapters.
- **Product:** [Compiled product v2](program-image-v2.md).

## Authoring and shared validation

Native Zig, the versioned authoring C ABI and Starlark construct the same typed
product through `compiler.author.Builder`. Author programs run on the build host.
Their loops, imports, functions and conditional construction finish before the
runtime graph is emitted. No frontend defines a second runtime expression
language or introduces language-specific semantic defaults.

Builder operations copy accepted inputs into builder-owned storage. They apply
the same bounded shape validation as the backend before serialization; final
emission resolves forward references, authority, migrations and graph cycles.
Source positions are diagnostic sidecars and do not affect product identity.
The C header owns ABI version negotiation, opaque-handle lifetime, buffer
ownership and status mapping. Starlark uses the pinned build-time worker through
this authoring boundary. Python, TypeScript, Go and Rust packages must follow
the same ownership and conformance vectors; their designs do not establish
implemented package support.

Serialized product JSON is an internal transport for emitted IR. The compiler
CLI accepts that output to separate frontend execution from isolated assembly.
It is not a recommendation that product authors manually write JSON.

## Compilation stages

| Stage | Inputs | Result and rejection boundary |
| --- | --- | --- |
| Author evaluation | Source modules and SDK | Typed model and source-map sidecar |
| Model validation | Product and declared target | Bounded IDs, references, authority and DAG |
| Input capture | Exact lock and explicit sources | Private immutable snapshots checked against length/digest |
| Content normalization | Captured source trees | Canonical pax files matching declared logical identities |
| Capability binding | Fixed Component bytes and published host contracts | Reflected imports, exports and exact WIT types |
| Emission | Normalized model and fixed inputs | Deterministic compiled product bytes |
| Assembly | Complete precompiled template, product and payload | Native image preserving executable code sections |
| Finalization | Assembled image and locked signer tool | Selected signature profile verified on final bytes |
| Publication | Verified image in private workspace | Atomic replacement of the destination |

All frontends share `compiler.pipeline.compile` and `build`; they must not
reimplement backend semantic checks. `compile` validates and emits the product.
`build` additionally captures sources, normalizes content, assembles and publishes.
Inspection uses the official engine through the isolated Component worker.
Known invalid WIT interface/function references fail during compilation.
Selected parameter and result types must be durable values; nested resources
and unsupported types fail even when a result has no downstream consumer.
Libraries may still export unselected resource APIs or use resources internally.
Input types are resolved from full reflected use-site types and recorded in the
emitted model. Defaults do not narrow standard enum or variant domains.

Input handles are not presumed immutable: capture hashes the bytes actually
copied. Inspection and signing callbacks with a `tool_id` receive the captured,
verified tool and captured library sources. Callback consumers must use these
private locators, not reopen the original author-supplied paths.

Raw source identity and canonical content identity are checked separately.
Normalization happens once per captured content source during a build. The outer
payload is a canonical pax tree containing fixed Components and canonical content
containers. Large source bodies and executable bytes use bounded positional
reads and streaming writes rather than whole-image allocations.

## Dependency and runtime resolution

The [compiler input lock](compiler-inputs-v1.md) fixes source kind, version,
digest, length, target and dependency IDs. Resolution supplies explicit sources;
the compilation path performs no floating version selection or network fallback.
Runtime metadata is a separately locked publication connected to the runtime
entry. It records the template digest, length, version and supported profile.
Digest agreement establishes identity; trusted acquisition establishes publisher
authority and remains a separate requirement.

The product's profile must equal the independently resolved runtime profile.
Library requirements and declared observations must fit that profile. Component
profile 1 rejects all callable imports at compile time; reusable pure type-only
imports remain valid. Host OS does not
select the target or reduce the supported cross-build matrix. A Linux x64
compiler can assemble PE, ELF and Mach-O products from complete precompiled
templates; no target execution, runtime compiler or linker is part of product
assembly. Product payload toolchains may impose their own independent limits.

`runtime-package` produces publication metadata by reading a template and
checking its native target/descriptor. It does not execute the target. Releasing
the Niobium runtime, assembling a product, publisher signing and real-OS
qualification are distinct processes with distinct evidence.

## Determinism, cache and concurrency

Author evaluation runs by default; native author programs may observe their
environment. Reproducibility claims require recording those external inputs.
The backend normalizes unordered collections while preserving parameter, list
and tuple order. Source maps are excluded. Deterministic unsigned assembly is
compared before signing, which may add timestamps or other variable metadata.

The current cache stores deterministic emission results. Its key includes the
compiler identity, stage, target, normalized model/profile, content/Component
profile options and complete fixed input lock. The CLI uses the running compiler
executable's SHA-256 as its identity. The shared API's development default is not
a production release identifier; embedders must supply their actual build ID.
The model portion of the cache key uses normalized author IR; exact library and
worker identities fix the type-resolution inputs. The cached output identity
includes the resolved input types and is checked against fresh emission.

A warm build still checks locks, types and content; a cache hit is validated
against newly produced canonical bytes. Corrupt records become misses; conflicting
valid bytes under one key are a determinism error.
Independent products use separate private workspaces and can compile in parallel.
Shared-cache publication uses immutable keys and atomic insertion. Parallel
author evaluation or inspection, persistent stage caches, selective invalidation
and performance qualification are subsequent work packages; the API does not
claim these optimizations are already implemented.

## Diagnostics, cancellation and output ownership

Diagnostics carry a stable `stage`, `code`, object `kind`, raw object ID, exact
cause and optional source position. Sidecar keys are qualified, for example
`call:configure` or `container:primary`, so unrelated ID namespaces cannot
capture one another's locations. Positions use nonempty UTF-8 paths and one-based
line/column numbers. The sidecar has `schema: 1` and `locations` entries and is
strictly decoded and bounded independently of the semantic model.

The backend accepts an atomic cancellation flag. Streaming captured input reads,
major stages and cache operations check it. Canceled compilation must leave the
previous published output intact. A callback is responsible for its own bounded
execution/cancellation; the Component client supplies process timeouts. The
current CLI does not yet expose a graceful signal-to-cancellation bridge.

Assembly creates a private workspace on the destination filesystem. File handles
and temporary outputs belong to that build. Output publication occurs only after
signature finalization when required, code preservation checks and final product
and payload verification. Mac templates require a finalizer; absence returns
`SigningRequired`. Atomic replacement does not by itself promise directory-entry
durability through sudden power loss on every platform.

## Executable interfaces and qualification

`niobium-compiler-v2 compile` requires `--program`, `--lock`, `--runtime`,
`--runtime-metadata`, `--worker`, repeated `--input id=path` and `--output`.
Optional `--source-map`, `--cache` and `--signer` select explicit diagnostic,
cache and signer inputs. Worker/signer IDs must be locked tool entries.
`runtime-package` takes `--template`, `--target`, `--version` and `--out`.

The supplied finalizer invokes pinned `rcodesign` and verifies the supported
ad-hoc Mach-O measurement profile. It does not implement Developer ID publication,
notarization or Authenticode. Those release workflows retain independent gates.

`N2-COMPILER-02` covers binding diagnostics, cache equality, cancellation and
canonical-source separation. `N2-COMPILER-04` covers the executable interface.
`N2-AUTH-02` covers equivalent Zig/C/Starlark construction. Native product tests
must execute final bytes; cross-host tests additionally isolate assembly from
Niobium source and runtime build tools. Compilation-only results cannot establish
target execution or publisher trust.
