# ADR-0024: Native runtime dependency qualification

- **Status:** Accepted
- **Date:** 2026-10-09
- **Amends:** [ADR-0023](0023-standard-content-and-component-contracts.md) (native runtime publication qualification)
- **Amended by:** [ADR-0025](0025-baseline-cpu-runtime-publication.md) (CPU publication contracts)

## Context

The retained binary policy describes the earlier installer artifacts, including
static musl Linux executables. The Component runtime integrates a pinned Rust
static archive and the selected native C ABI. A static library does not imply a
freestanding executable or eliminate operating-system runtime dependencies.

Checking the delivered Windows GNU images against the retained policy rejected
six exact Universal CRT API sets and the synchronization API set used by Rust.
An empty Zig executable linked with libc reproduces the six CRT imports; adding
`-static` does not remove them. The Rust GNU target does not provide the MSVC
target's switchable CRT linkage. Replacing native runtime shims solely to satisfy
the earlier artifact policy would introduce another ABI implementation.

The Universal CRT is an operating-system component in Windows 10 and later.
API-set import names identify versioned loader contracts, rather than requiring
files with those names. These facts do not qualify every Windows device or a
particular Niobium runtime. The actual imports and target execution still require
their own evidence.

The measured Linux GNU runtime imports `libc.so.6` and `ld-linux-x86-64.so.2`,
with interpreter `/lib64/ld-linux-x86-64.so.2`. Its symbol-version table requires
GLIBC_2.36. The current execution evidence is Ubuntu 24.04; this measurement
does not establish qualification on older distributions.

## Decision

1. Native runtime publication uses a separate `component` binary policy. The
   independent binary checks retain their own declared artifact scope. Artifact kind and dependency profile are independent selectors.
2. Each Component rule identifies OS, CPU and native ABI. Linux GNU and musl
   have separate rules; musl requires no dynamic interpreter or dependency.
   GNU requires its exact loader and declared system dependencies. Missing or
   unqualified selectors fail publication.
3. Dependency rules contain exact measured names. The Windows GNU rule permits
   only its observed system DLLs, six UCRT API-set contracts and synchronization
   contract. Wildcard API-set allowances, toolchain DLLs and implicit local CRT
   redistribution are forbidden. Additional dependencies require a reviewed
   rule and new target evidence.
4. The profile checks expected native format, dynamic interpreter and all
   existing executable hardening requirements. Dependency declarations cannot
   suppress ASLR, NX, high-entropy VA, writable-executable or executable-stack
   failures. Runtime publication and the mandatory standard-core gate use it.
   Each native ABI also has a measured runtime-size baseline: publication enforces
   the 30 MiB ceiling and the existing five-percent growth bound. Product payload
   capacity is a separate image-container limit.
5. A binary policy records native prerequisites; it grants no guest authority.
   Product assembly still copies fixed runtime bytes without target execution
   or relinking. Published-template identity includes the native import tables.
   Target qualification records the actual OS, ABI, filesystem and privileges.

## Consequences

The standard runtime can use qualified operating-system interfaces without
loosening retained artifact checks. A GNU Linux runtime retains its glibc
prerequisite; a musl runtime remains independently qualified as static. Neither
cross-assembly nor an import-table check establishes target support alone.

MSVC and other unmeasured native ABI profiles remain unqualified until their
exact imports, runtime packaging and execution have been checked. Native profile
expansion is a runtime publishing task, separate from capability-library changes.

## Sources and validation

- [Microsoft: Universal CRT deployment](https://learn.microsoft.com/en-us/cpp/windows/universal-crt-deployment?view=msvc-170)
- [Microsoft: Windows API sets](https://learn.microsoft.com/en-us/windows/win32/apiindex/windows-apisets)
- [Rust: static and dynamic C runtimes](https://doc.rust-lang.org/reference/linkage.html#static-and-dynamic-c-runtimes)
- First delivered-image findings: `.evidence/native-binary/20261008T154120Z/`.
- Tests must prove that the retained profile still rejects the new imports,
  undeclared imports fail the Component profile, static ELF rejects an interpreter,
  and every hardening failure remains fatal under both profiles.
