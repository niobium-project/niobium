# ADR-0025: Baseline CPU targets for runtime publication

- **Status:** Proposed
- **Date:** 2026-10-09
- **Amends:** [ADR-0023](0023-standard-content-and-component-contracts.md) (runtime publication), [ADR-0024](0024-native-runtime-dependency-qualification.md) (CPU qualification)

## Context

The published profile identifies OS, CPU architecture and native ABI. Using the
build host's detected CPU features can silently require a newer ISA than that
architecture's baseline. Zig 0.17 resolves an unspecified native CPU model using
host detection. A template built on a newer runner can therefore carry an
undeclared CPU prerequisite.

The cross-runtime entries already specify their architecture. Native publication
must apply a complete CPU policy independently of build-time author and compiler
tools. Changing only the Zig graph cannot constrain machine code already present
in the Rust archive. Wasmtime also compiles a Unix C helper through the `cc` crate.

## Decision

1. Native runtime publication creates its own module graph with explicit OS,
   architecture, ABI and `cpu_model = .baseline`. All transitive Zig and native C
   modules use that target. Host tools and author SDKs retain their own build-host
   targets; they do not enter the delivered runtime graph.
2. The pinned Rust engine archive must use its declared standard target CPU
   configuration. The publication baseline includes every code generator: Rust
   defaults, highest-priority encoded Rust flags, Cargo configuration, native C
   helper flags and compiler/wrapper provenance. Windows Rust x64 defaults include
   `cmpxchg16b`, `sse3` and `lahfsahf`; Darwin arm64 uses Apple M1. Architecture
   names alone must not be interpreted as those complete CPU requirements.
3. Runtime packages and published host SDKs declare their complete minimum CPU
   profile. Host-specific overrides cannot qualify as a generic publication.
   Specialized CPU profiles require a distinct publication and compatibility
   and execution evidence. Supplied cross archives carry the same provenance.
4. Product assembly continues to copy the complete template unchanged. Selecting
   baseline CPU features does not weaken the native dependency, size, signature
   or executable-prefix checks. OS and native ABI prerequisites remain separate.

## Consequences

The publisher's machine no longer silently changes the runtime's minimum CPU
features. Published bytes and their identities change when the build target
changes; existing setup evidence must not be reused for a different template.
Baseline compilation alone does not qualify every operating-system version or
prove execution on every physical CPU. Those remain platform acceptance claims.

This proposal is not implemented. Current native publisher evidence remains
specific to its recorded host CPU; it establishes no generic CPU portability
claim. The proposed profile requires a coordinated change to native publishing,
runtime package metadata and SDK publication before that claim can be made.

## Validation

Inspect the runtime build command for the explicit baseline CPU and verify that
the runtime graph contains no author/compiler modules. Rebuild and identify the
template, then repeat source-free assembly and execute those exact delivered
bytes. Retain native dependency/hardening checks and real lifecycle assertions.
