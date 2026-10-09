# Wasm library SDK

- **Kind:** Engineering design for [capability-library-v2](../spec/capability-library-v2.md).
- **Owners:** Versioned WIT, Component tooling, `component_worker` and library publishers.
- **Current boundary:** Generated C/Rust consumers, production Component inspection and
  calls, fixed libraries, typed dataflow and explicit state migration are implemented.

## Library and author boundaries

A library's WIT interface identifies its contract and types. Its locked package
version and digest identify one implementation. Call identity, state version and
migration rules belong to the product graph. Two calls of one implementation have
separate grants and state ownership, including calls with no private state.

Build-time author helpers construct the product graph; runtime Components compute
values and resource proposals. These may ship together, but runtime never executes
author helpers. Official `stdlib.files` and the independent toolchain consumer
use the same contract, worker, validation and ownership boundaries.

The standard [WIT proposal package](../../api/wit/runtime/proposal.wit) defines
content references, generated entries, desired placement and access intent. A
library may define a structural plan with its own concrete private-state type
and additional typed result fields. The host preserves those fields for downstream
calls while replacing generated trees with canonical host-computed references.

## Standard ABI and execution profile

Upstream `wit-bindgen`, `wasm-tools` and Wasmtime implement generation, Component
encoding and the Canonical ABI. Niobium does not define a parallel guest memory
layout. Replacement of these implementations follows
[ADR-0026](../adr/0026-pinned-rust-component-wasm.md). The
[capability contract](../spec/capability-library-v2.md) owns enabled
features, imports, buffer ownership, execution limits and error behavior.

Production calls use prebound observations and values. Resource-free type-only
imports require structural validation and grant no callable authority. Callable
imports need a separately qualified profile; the current compiler rejects them.
Transient Component resources are supported inside an evaluation session, as
qualified by the engine tests. Resource handles cannot cross durable process IPC,
compiled values or frozen plans.

The native runtime uses disposable workers with Wasmtime/Pulley. Parent-owned
allocation, output, deadline and cancellation bounds complement engine fuel and
memory limits. The runtime captures its executable image before interpreting
product metadata, and pins worker execution to verified private bytes. A failed
invocation discards its session and proposals.

## Packaging and tooling

A library publication contains standard Component bytes, WIT sources/dependencies,
license/provenance, build-time helpers where needed and conformance vectors. The
compiler lock fixes library, tool and runtime identities. Package registries and
publisher catalog immutability checks remain a separate distribution service.

The current build graph creates an independent WIT workspace for each consumer,
using the canonical common package as a fixed dependency. Shared source contracts
are not copied into several maintained implementations. Runtime does not search
for replacement libraries or deserialize untrusted engine cache artifacts.

The [Component SDK guide](../development/component-library-sdk.md) provides current
commands and examples. A development host must use production validation and
budgets. Future package inspection, generated author conveniences and additional
guest languages must demonstrate the same contract with independent consumers.

## Conformance and evolution

| Concern | Required evidence |
|---|---|
| Values and bindings | Lossless integers, UTF-8, bytes, records, variants, options/results and typed cross-library projections |
| Capability boundary | Compiler/runtime agreement on selected signatures; no ambient imports or durable resource handles |
| Execution | Initialization rejection, instruction/memory/allocation/output quotas, cancellation and parent deadline |
| Content | Fixed references and generated trees, confinement, host identity, authority and per-grant budgets |
| State | Fresh release state, explicit conversion, missing/incompatible paths and immutable applied identity |
| Independence | External consumer changes resources without rebuilding the runtime; recovery executes no guest |

Adding a new machine primitive requires a runtime implementation, authority
contract and recovery semantics. Adding a product policy using existing primitives
requires a library/preset change. Changes to WIT or state compatibility require
versioned contracts and vectors before parallel implementations begin.

The retained Core Wasm/WAMR profile and `capability.h` remain v1 interfaces with
historical evidence. Their custom pointer/index conventions do not constrain the
Component SDK.
