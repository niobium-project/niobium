# ADR-0023: Standard content, component contracts and cross-host compilation

- **Status:** Accepted
- **Date:** 2026-10-08
- **Amended by:** [ADR-0024](0024-native-runtime-dependency-qualification.md) (native runtime publication qualification)
- **Amends:** [ADR-0022](0022-installer-dsl-and-aot-toolchain.md) (contract representation and runtime qualification), [ADR-0005](0005-tar-zst-artifact-format.md) (new content profile), [ADR-0001](0001-repository-baseline-and-zig-only-toolchain.md) (pinned external toolchains)

## Context

The executable DSL baseline establishes build-time authoring, fixed libraries and
guest-independent recovery. Its opaque byte inputs, file-only outputs, bounded
Mach-O slot and macOS-only build entry do not establish a general content model
or cross-host compiler. Product composition requires several artifacts per
component, content transformations, observations, scoped effects and maintenance.

The implementation plan was approved on 2026-10-08. The standard Component host
passed its macOS arm64 qualification gate, including generated C/Rust consumers,
typed values and resources, forbidden imports, initialization and execution
budgets. Its adoption does not retroactively change v1 evidence or qualify other
OS, architecture and scope combinations.

## Decision

1. The core has four primitive families: content; machine state; authority and
   ownership; execution and maintenance. Product selection, coexistence and
   responses to missing prerequisites remain product policy.
2. A content container is a bounded hierarchical snapshot of files, directories
   and explicit symbolic links. Its logical identity is independent of source
   location and transport encoding. A versioned POSIX pax/tar profile owns its
   canonical representation; Niobium does not introduce a new archive encoding.
   The retained artifact-v1 layout and its no-link rule keep their original scope.
3. Source bytes, logical content, derivation, deployment resources and final
   delivered images have separate identities. A reference does not grant write
   authority. Runtime derivation may produce members only within fixed library,
   source, output and budget declarations. The host freezes their bytes and
   resource inventory before executing machine effects.
4. WIT owns capability interface types. Reuse upstream parsers, guest generators
   and Canonical ABI implementations. Use pinned Wasmtime Component C API with
   Pulley. Zig remains the native core language; pinned
   Rust tooling and libraries are permitted for this integration. Do not replace
   a failed qualification with an unreviewed custom ABI or weaker budgets.
5. The Component profile has no ambient WASI, filesystem, network, process or
   privilege authority. It disables native JIT and guest threads. Standard Wasm
   is validated; untrusted engine-serialized artifacts are not accepted. Loading,
   initialization, guest calls, canonical allocation and cleanup require their
   own bounded execution evidence.
6. A unified access contract expresses a strict portable subset for installation
   owners and other users. Native backends implement and verify its effects.
   Archive metadata is not an authorization grant. Unsupported rules, filesystem
   capabilities and unmanaged ACL changes produce explicit outcomes.
7. Host tools, target runtimes and product payload toolchains have separate build
   identities. Linux x64 product assembly must produce Windows x64, macOS arm64
   and Linux x64 setups using precompiled runtime packages without target code
   execution, runtime source access or product-specific relinking. Signing uses
   pinned tools available on the build host. Real target execution is a separate
   qualification stage, not a product-build prerequisite.
8. The compiler has explicit evaluation, validation, locking, normalization,
   binding, emission, assembly and signing boundaries. Author programs are
   reevaluated by default. Backend caches use fixed semantic inputs and verified
   outputs; cancellation and publication failures preserve prior valid output.
9. Public authoring, library, program and durable-state contracts evolve through
   new versions. The new baseline rejects incompatible PoC state before mutation;
   it does not silently reinterpret v1. Recovery consumes frozen host plans and
   never requires a guest, an author program or a newly resolved dependency.

Resource-free, nonempty type-only Component imports carry no callable authority.
The compiler and host validate them structurally through the same bounded WIT
contract. Callable imports need explicit primitive contracts and bindings;
WASI namespaces, unknown callable imports and transient resources in durable
values remain forbidden. Product v2 currently uses read-only host observations
as typed arguments and returns declarative resource proposals.

## Qualification and consequences

New acceptance rows distinguish contracts, executable implementation and target
qualification. Existing N1 and N2 evidence retains its original format, engine,
target and scope. A format test does not establish native execution or effective
access rights. Publisher certificate signing and notarization have separate
qualification from ad-hoc signing and native launch.

The adoption gate is recorded in
`.evidence/component/20261008T122619Z-da5481dddae91a1a` and
`.evidence/component-ipc/20261008T123933Z-0c727cd8b9e9c81d`.
The latter includes parent cancellation and deadline enforcement. These local
records identify their own source snapshots; later integration evidence must
identify the final delivered bytes again.

The first unified access profile excludes arbitrary principals, deny rules,
inheritance editing, unknown ACL merging and a portable directory-traversal-denial
guarantee. The host must not approximate these requirements by expanding rights.

Advanced registries, remote caches, complete language SDK packages, GUI, additional
system integrations and bridge-release orchestration remain separate work. Their
interfaces must preserve the four families and the fixed authority boundary.

## References

- [POSIX tar/pax representation](https://github.com/libarchive/libarchive/blob/master/libarchive/tar.5)
- [Reproducible tar archives](https://www.gnu.org/software/tar/manual/html_node/Reproducibility.html)
- [WIT](https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md)
- [Wasmtime Component C API](https://docs.wasmtime.dev/c-api/component_2component_8h.html)
- [Pulley interpretation](https://docs.wasmtime.dev/examples-pulley.html)
- [Windows file access](https://learn.microsoft.com/en-us/windows/win32/fileio/file-security-and-access-rights)
