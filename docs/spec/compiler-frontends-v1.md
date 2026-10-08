# Compiler frontends v1

- **Status:** Normative target; implementation evidence is in [N2 acceptance](../acceptance-plan-v0.2.md).
- **Decision:** [ADR-0022](../adr/0022-installer-dsl-and-aot-toolchain.md).

## Authoring boundary

A product author runs a program on the build machine. That program constructs the
typed model defined by [program-image-v1](program-image-v1.md). Loops, functions,
conditions and project composition use the author's language. The compiler never
requires authors to encode JSON, hex payloads or a second expression language.

Native Zig/C and Starlark are the initial frontend contracts. Python, TypeScript,
Go and Rust SDKs wrap the same authoring C ABI. The latter SDK packages have
separate acceptance; listing a language here does not claim its package exists.
Starlark evaluation belongs to the build process and never enters setup.
The Go worker pins `starlark-go` through `apps/starlark/go.mod` and `go.sum`.
Its build requires Go 1.25 or newer and a host C compiler for cgo. The worker
limits source bytes, module loading and evaluation steps; it is not a sandbox
for arbitrary native author programs.

All frontends share validation, normalization and serialization. An equivalent
product built through two frontends must produce the same normalized program.
Guest binding order remains significant, as specified by the program owner.

## Native and C interfaces

`libs/program` owns the native `Program` types and semantic checks. The compiler
consumes those types rather than maintaining another schema. Native APIs accept
explicit allocators and return explicit errors.

`api/c/compiler.h` owns the authoring ABI. Its prefix is `nbc_`; the old `dist_`
runtime embedding API does not define authoring semantics. The ABI has opaque
builders, typed product setters, entry addition and instance binding functions,
normalization/emission, and explicit destruction and error retrieval.

No Zig slice, allocator, error union or layout crosses C. Strings and buffers have
explicit lengths. A returned owned buffer has a matching release function. The header defines error text as borrowed static names; a successful operation
clears the builder's current error. Builders must be destroyed exactly once. Failed operations leave no partially accepted program entry.

SDKs expose host-language objects and exceptions over these operations. They may
read library and asset files through bounded build-time APIs. SDKs do not introduce
language-specific defaults into the model. A frontend's package version is
independent of the program format and runtime/library ABI versions.

## Compilation

The compiler performs these stages before publishing any output:

1. Evaluate the author program and collect the typed model with diagnostic context.
2. Validate identifiers, references, paths, migrations, limits and blob digests.
3. Normalize unordered collections and preserve ordered instance bindings.
4. Validate every library against the restricted Wasm profile and capability ABI.
5. Check the selected complete runtime's target, ABI and image capacity.
6. Embed the normalized program into that runtime and write the final setup.
7. Apply platform signing at the compiler application boundary.

The first executable backend targets macOS arm64 and invokes ad-hoc `codesign`.
Release publisher signing and Windows/Linux image backends are separate work
packages. The template executable is built independently of every product.
Compiler packaging must not relink it or build product-specific runtime code.

The compiler records the template digest separately from the final setup digest.
Author inputs and library bytes are frozen in the program. No installation-time
dependency resolution or author-source evaluation fills in missing information.

## Reproducibility and failures

Reproducibility compares normalized program bytes and unsigned setup construction
for fixed inputs. External author programs can observe their build environment;
the compiler does not claim to sandbox arbitrary native author code. Build
provenance must record inputs before a release claims reproducibility.

Errors identify the failing stage and object ID. C and language bindings preserve
the same failure category. Invalid inputs, conflicting identities, unresolved
references, incompatible libraries, over-limit programs and malformed templates
fail before a deliverable is presented as valid.

## Acceptance

- `N2-AUTH-01`: Zig/C and Starlark author the same program with identical normalized bytes.
- `N2-AUTH-01`: C ownership, failed operations and error lifetime behave as documented.
- `N2-AOT-01`: two products use one unchanged runtime template without relinking.
- `N2-IMAGE-01`: final signing is applied after embedding; capacity and malformed-template failures are explicit.
- `N2-SDK-01`: Python/TypeScript/Go/Rust packages pass the shared frontend vectors.

Compiler implementation structure is in [compiler engineering](../design/compiler-engineering.md).
