# ADR-0022: Installer DSL and AOT toolchain

- **Status:** Accepted
- **Date:** 2026-10-08
- **Amended by:** [ADR-0023](0023-standard-content-and-component-contracts.md) (standard content, Component contracts and cross-host compilation)
- **Amends:** [ADR-0001](0001-repository-baseline-and-zig-only-toolchain.md) (toolchain scope), [ADR-0004](0004-tuf-profile.md) (distribution policy ownership), [ADR-0008](0008-shared-software-renderer.md) (standard UI scope), [ADR-0020](0020-distribution-delivery-milestones.md) (distribution implementation model)

## Context

Niobium must let product authors compose installers for optional modules, SDKs and
toolchains, and declare their own distribution and upgrade policies. A fixed JSON
product schema and repository-only feature modules make those policies framework
decisions. Extending that schema with expressions would create an authoring
language without the tooling of an established programming language.

Niobium is a domain-specific language for installation
and distribution, with an AOT compiler, a precompiled runtime and capability
libraries. The project may reset its pre-release APIs and state formats. Existing
implementation evidence does not establish that the new architecture is complete.

## Decision

1. Product source is a build-time program. Native Zig/C authoring, C-ABI-based
   Python, TypeScript, Go and Rust SDKs, and a build-time Starlark frontend share
   one product model. Source-language evaluation finishes before distribution.
   JSON or another serialization may carry machine data; authors are not required
   to express product logic in JSON or YAML.
2. The compiler evaluates author input, validates the product model and capability
   contracts, resolves and freezes library identities, and packages a setup. It
   does not compile a product-specific copy of the runtime.
3. The runtime is a complete, independently compiled executable. A setup contains
   that executable, a compiled product program, fixed precompiled libraries and
   the selected product artifacts or their authenticated references. The compiler
   preserves the immutable template input and executable code sections. Embedding
   fills the reserved product section in an output copy; final signing changes
   output signature metadata as a separate release step.
4. A capability contract defines typed inputs, outputs, required host authority,
   state and lifecycle obligations. Its implementation is a host-controlled Wasm
   capability library. Official standard libraries and product or third-party
   libraries use the same contract and binding mechanism.
5. Wasm code has no ambient filesystem, process, network or elevation authority.
   The runtime grants explicit host operations through checked interfaces and
   bounds execution, memory and input. A declared contract never grants itself
   permission. Machine effects use host-owned validation, journaling and recovery.
6. Core owns composition mechanisms, compatibility checks, resource identity,
   authority and transactional execution. Component selection policy, SDK
   coexistence, channels, deployment layouts and product recommendations belong
   to libraries, presets and templates. Standard UI and distribution profiles are
   implementations above core.
7. The published program is fixed before installation. A deployment plan is
   derived later from that program, explicit choices and observed machine state,
   and is frozen before mutation. Recovery uses the recorded program and library
   identities, never a newly resolved implementation.
8. Products declare supported upgrade sources, migrations, bridge requirements
   and refusals. Core validates and executes those declarations. The draft framework gives no cross-version compatibility guarantee. Product
   and library identities still require explicit validation. Business data
   remains owned by the product; no database rollback guarantee is inferred from
   deployment rollback.
9. The initial reset does not require a bridge from the old manifest, C ABI or
   installed-state formats. Breaking framework changes may occur at any time. Unknown persisted formats
   refuse before mutation; no silent conversion is permitted.

ADR-0020's online installer, complete offline file and SFX milestones remain
planned delivery outcomes. Their implementations use the compiled program,
precompiled runtime and capability-library contracts defined here. This amends
ADR-0020's fixed-manifest/shared-engine and closed-extension assumptions; release
authorization, strict extraction, transactional effects and final-byte qualification
remain required by the selected distribution profile. The bounded macOS carrier
PoC does not complete the cross-platform delivery milestones.

ADR-0021's pinned CI evidence transport and the test-system protocol retain their
independent scope. Build-time language frontends do not expand transport authority
or place AWS CLI in product runtimes.

The normative owners are the compiler frontend, program image, capability library,
runtime lifecycle and migration specifications indexed in [docs/README](../README.md).
Implementation sequencing and independent work packages belong to the
[current roadmap](../roadmap.md). Results belong to the N2 acceptance plan.

## Consequences

- The old repository-only module and JSON preset proposals are superseded. Current ADRs are consolidated in place under ADR-0016.
- Zig remains the language of the native compiler/runtime implementation. Product
  authoring languages and Wasm library toolchains are separate consumers.
- Existing trust, extraction, platform, UI and transaction code can be reused where
  it satisfies the new contracts. Reuse does not carry old product-policy constraints
  into core or transfer old acceptance results to new interfaces.
- Every setup fixes its runtime, program and library compatibility set. Library
  extensibility requires a Wasm host ABI, conformance tests and retained recovery
  implementations. It does not authorize arbitrary native library loading.
- Work that affects these boundaries updates its owning specification before code.
  Documentation labels planned interfaces and actual implementation separately.
