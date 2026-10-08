# Wasm library SDK

- **Kind:** Implementation design for [capability-library-v1](../spec/capability-library-v1.md).
- **Audience:** Capability authors and host maintainers.
- **Implementation boundary:** The PoC uses ABI v1 with Zig/C declarations and embedded Wasm. Package tooling and generated higher-level bindings are follow-on work.

## Library model

A library has a contract identity, contract version, implementation version and content digest. A capability instance supplies ordered bindings and owns its persisted state. Two instances of one library have separate authority and state.

The contract describes input and state types, required host primitives, produced resource classes and lifecycle obligations. Build-time author helpers construct instances of that contract. Runtime Wasm implements planning and migration. A library package may ship both parts, but installing a setup never evaluates the author helpers.

The first wire profile represents input and state values as bounded byte strings. Rich typed wrappers validate and encode those values at the library boundary. They do not add product-specific fields to the global program model. A richer generated type description requires an explicitly versioned package contract before implementation.

Official libraries receive no special imports or unchecked execution path. An external library that uses the same existing primitive set requires no runtime rebuild.

## ABI and generated bindings

The normative import/export table is in [capability-library-v1](../spec/capability-library-v1.md); `api/c/capability.h` is the C declaration owner. The Zig guest facade uses matching integer widths and module/export names. Guest allocators remain private to Wasm memory.

The SDK provides checked reads, resource emission and state emission over the ABI. Reads return a byte count or a negative error. Callers must treat insufficient capacity as failure; truncation cannot silently change an input. All host copies finish before the import returns.

Guest planning returns zero after computing its desired output set. Granted
resource handles permit emission; omitted resources are absent from the next
generation. A capability may enforce its own required outputs. A nonzero return, trap or host rejection invalidates the entire evaluation. Handles are scoped indices from the current instance, never paths, OS descriptors or host addresses.

Migration runs before planning and passes its resulting state to that planning invocation. Both calls share the evaluation budget. The SDK must not hide failed migration behind an empty state or reset fuel by recreating an invocation.

Binding generation takes the versioned capability description as its input and emits language-specific helpers, contract metadata and test vectors. Hand-written ABI v1 declarations are the PoC baseline. Generated declarations must preserve their calling convention and errors exactly.

## Package and dependency design

A future distributable package contains a versioned descriptor, one Wasm implementation, build-time author bindings, license/provenance and conformance vectors. The descriptor fixes the contract and implementation identities, module digest, ABI/profile and required host primitives.

The compiler lockfile pins the complete package identity and each selected blob. The compiler verifies the descriptor against the module imports and runtime profile. A descriptor can request authority but cannot grant it. Host grants derive from the bound product instance and runtime policy.

ABI v1 does not dynamically link Wasm modules. A library author links reusable guest code into one module at library build time. Runtime never searches the filesystem or network for an implementation. Additional component-model or linking support requires a separate versioned profile.

Publishing tooling rejects changed contents under an existing immutable version. Installed-state history verifies applied migration identity where records exist. A publisher's catalog provides additional historical checks; a local build cannot prove a remote history it was not given.

## Host implementation

WAMR classic interpreter is pinned under `third_party/wamr`. Engine configuration and provenance must establish that JIT, the Wasm AOT engine, WASI, threads and automatic module loading are absent. Instruction accounting must cover every guest instruction that the enabled interpreter accepts.

The compiler and runtime share bounded profile validation. Engine validation then checks full Wasm semantics. Start sections and implicit initialization exports are rejected before instantiation; explicit calls use the same budget as planning.

Host context belongs to the module instance. The adapter validates pointer arithmetic, memory ranges, handles, duplicate emissions and aggregate limits before copying data. Host IO is outside guest callbacks. Guest output becomes host-owned only after all checks succeed.

Global engine initialization has a single lifetime owner. The first implementation may serialize evaluation; this limits throughput but avoids interleaved global engine state. Parallel execution requires an engine lifecycle and per-instance budget test, without changing the guest ABI.

## Conformance and developer tools

The conformance runner loads a package using the production profile checker and host adapter. A standalone test host can supply facts and state without touching a machine. It must use the same adapter rather than a permissive mock import set.

| Vector family | Required observations |
|---|---|
| Binding | Each input/asset/resource index reaches only its declared instance |
| Data | Empty, maximum-size and multibyte inputs preserve exact bytes |
| State | Fresh state, compatible state, migration and migration failure |
| Authority | Unknown import, WASI, invalid handle and cross-instance access rejected |
| Memory | Overflowing pointer/length, out-of-range buffer, growth and output ceilings |
| Execution | Infinite guest loop, recursion, start behavior, trap and nonzero status |
| Output | Duplicate resources, omitted grants, excessive state and partial failure |
| Reuse | Repeated evaluation does not retain another instance's state or budget |

PoC acceptance requires an external consumer that imports only the public guest SDK. Changing that consumer's code must change the observed product output with the same runtime template. Compiling a module without executing it cannot establish conformance.

Developer tooling later adds package inspection, local test-host execution and source-map diagnostics. These tools stay outside the runtime dependency graph. [N2 acceptance](../acceptance-plan-v0.2.md) records proof; [the roadmap](../roadmap-v0.2.md) defines implementation packages.
