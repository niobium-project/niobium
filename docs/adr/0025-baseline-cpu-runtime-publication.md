# ADR-0025: Baseline CPU targets for runtime publication

- **Status:** Accepted
- **Date:** 2026-10-09
- **Amends:** [ADR-0023](0023-standard-content-and-component-contracts.md) (runtime publication), [ADR-0024](0024-native-runtime-dependency-qualification.md) (CPU qualification)

## Context

The published profile identifies OS, CPU architecture and native ABI. Using the
build host's detected CPU features can silently require a newer ISA than that
architecture's baseline. Zig 0.17 resolves an unspecified native CPU model using
host detection. A template built on a newer runner can therefore carry an
undeclared CPU prerequisite.

The delivered Linux setup in CI run `37835115025` terminated at an `INSERTQ`
instruction requiring SSE4a. Its template and executable code section match the
earlier successful run's bytes; assembly did not introduce the instruction. A
separate emulated replay failed earlier on `SHA256MSG1` in the transferred witness
and setup. The evidence establishes undeclared instruction-set requirements, not
the source symbol of the stripped runtime's `INSERTQ` instruction. The first
failure is retained in `.evidence/core-ci/20261009T020130Z-linux-sigill/`.

The cross-runtime entries already specify their architecture. Native publication
must apply a complete CPU policy independently of build-time author and compiler
tools. Changing only the Zig graph cannot constrain machine code already present
in the Rust archive. Wasmtime also compiles a Unix C helper through the `cc` crate.

## Decision

1. Native runtime publication creates its own module graph with explicit OS,
   architecture, ABI and `cpu_model = .baseline`. All transitive Zig and native C
   modules use that target. Published compilers, author SDK libraries, Component
   workers, Starlark executables and transferred qualification witnesses also use
   explicit publication targets. Build-only test runners may use the detected
   host target; their modules must not enter published artifacts.
2. The pinned Rust engine archive must use its declared standard target CPU
   configuration. The publication baseline includes every code generator: Rust
   defaults, highest-priority encoded Rust flags, Cargo configuration, native C
   helper flags and compiler/wrapper provenance. Windows Rust x64 defaults include
   `cmpxchg16b`, `sse3` and `lahfsahf`; Darwin arm64 uses Apple M1. Architecture
   names alone must not be interpreted as those complete CPU requirements.
   Ambient Rust flags/configuration cannot override the selected target. C-helper
   flag families are cleared before explicit flags are applied, including every
   host/target spelling; compiler wrappers and default-suppression settings are
   controlled. Published Go/CGO outputs likewise fix their architecture level,
   compiler and effective flags instead of inheriting host-specific overrides.
3. Runtime packages and published host SDKs declare their complete minimum CPU
   profile. Host-specific overrides cannot qualify as a generic publication.
   Specialized CPU profiles require a distinct publication and compatibility
   and execution evidence. Supplied cross archives carry the same provenance.
   [Runtime-package v2](../spec/runtime-package-v2.md) requires a versioned
   `native_profile` identifier supplied by the publisher build configuration.
   Native headers cannot prove that declaration. SDK inventories identify each
   artifact separately, including prebuilt signing tools outside these compilers.
4. Product assembly continues to copy the complete template unchanged. Selecting
   baseline CPU features does not weaken the native dependency, size, signature
   or executable-prefix checks. OS and native ABI prerequisites remain separate.

## Consequences

The publisher's machine no longer silently changes the runtime's minimum CPU
features. Published bytes and their identities change when the build target
changes; existing setup evidence must not be reused for a different template.
Baseline compilation alone does not qualify every operating-system version or
prove execution on every physical CPU. Those remain platform acceptance claims.

Earlier publisher evidence remains specific to its recorded host CPU; it does
not qualify the new publication contract. New bytes require fresh source-free
assembly and target execution evidence. Schema and build-setting checks alone
cannot establish minimum-CPU execution.

## Validation

Inspect the runtime build command for the explicit baseline CPU and verify that
the runtime graph contains no author/compiler modules. Rebuild and identify the
template, then repeat source-free assembly and execute those exact delivered
bytes on a recorded CPU lacking SSE4a and SHA extensions. Exercise compiler,
Component worker, Starlark and transferred witnesses as well as the setup
lifecycle. Hostile ambient Rust/C/Go flags must be rejected or replaced by the
declared settings. Retain native dependency/hardening checks and real lifecycle
assertions. Do not reject every advanced opcode in a binary: correctly guarded
runtime-dispatched implementations may contain them.

## Sources

- [Cargo Rust flag precedence](https://doc.rust-lang.org/cargo/reference/config.html#buildrustflags)
- [Wasmtime 49.0.2 native C-helper build](https://github.com/bytecodealliance/wasmtime/blob/v49.0.2/crates/wasmtime/build.rs)
- [Rust 1.96.1 Windows GNU target defaults](https://github.com/rust-lang/rust/blob/1.96.1/compiler/rustc_target/src/spec/targets/x86_64_pc_windows_gnu.rs)
