# Runtime publishing and cross-host product assembly

This workflow separates author execution, runtime publication, product assembly
and target qualification. The compiler can assemble Windows x64, macOS arm64 and
Linux x64 products on Linux x64 from fixed published inputs. A product's own
payload toolchain may have additional requirements; Niobium assembly does not
execute the target or compile/link its runtime.

## Build the host SDK and a runtime template

Source builds use Zig 0.17.0, Rust 1.96.1 and Go 1.25 or newer. Rust is needed to
publish the Component engine/runtime; Go and a host C toolchain build the Starlark
worker. Neither toolchain is needed inside isolated product assembly.

```sh
rustup toolchain install 1.96.1 --profile minimal
rustup +1.96.1 target add wasm32-unknown-unknown
zig build core-sdk
zig build core-test
```

The Rust native target must match the Zig host ABI. The graph passes that target
explicitly instead of using rustup's default host. Linux GNU uses
`x86_64-unknown-linux-gnu`, macOS arm64 uses `aarch64-apple-darwin`, and GNU Windows
uses `x86_64-pc-windows-gnu`. On a Windows installation whose default Rust host is
MSVC, add the GNU target before running the build:

```sh
rustup target add --toolchain 1.96.1 x86_64-pc-windows-gnu
```

GNU Windows also needs an x64 MinGW C compiler and `dlltool`; set `CC` explicitly
for Starlark's CGO build. The native CI checks the compiler target and records its
resolved path/version. A Zig MSVC host instead selects the matching Rust MSVC
archive; it must not consume a GNU archive.

Runtime publication runs the `component` binary policy under
[ADR-0024](../adr/0024-native-runtime-dependency-qualification.md). It checks exact
system dependencies and executable hardening using native ABI selectors. Linux
musl requires no dynamic loader or dependencies; the measured GNU template uses
the system glibc loader and requires GLIBC_2.36 symbols. Windows GNU uses the
declared system UCRT and synchronization API sets. These are target prerequisites,
independent of the product assembly host. An unqualified ABI, including MSVC,
fails publication until its own rule and execution evidence are provided.

Current native SDK/runtime builds use the detected host CPU target. Qualification
records the actual host and its Zig target, so these artifacts are not claimed to
run on every CPU of the same architecture. Generic CPU publication requires the
coordinated Zig, Rust and C-helper controls in
[proposed ADR-0025](../adr/0025-baseline-cpu-runtime-publication.md); it is a separate
publisher work package. Product assembly continues to consume fixed bytes.

The build graph fetches hash-pinned `wasm-tools`, `wit-bindgen` and portable guest
libc headers/libraries. `core-sdk` installs the compiler, authoring C library/header,
Starlark and Component workers, complete host runtime template, runtime-package
metadata, common WIT, official files Component, two independent consumer releases,
and the pinned host `rcodesign` executable with its copying notice under `zig-out/`. Native Zig author projects consume the public `compiler.author`
module through the repository/package build graph.

The runtime publisher supplies a complete template for each target, its profile
metadata and exact digest. `runtime-package` inspects a template without launching it:

```sh
niobium-compiler-v2 runtime-package \
  --template runtime-template \
  --target aarch64-macos --version 0.3.0-dev --out runtime-package.json
```

The declared target must match the native image and template profile marker.
Publishing requires evidence that this runtime implements the advertised profile;
metadata generation alone does not establish that claim. The Windows runtime
contains an `asInvoker` application manifest. Both native and cross publication
compile it with Zig's bundled resource compiler; the distributed template needs
no separate `.res`, manifest file or Windows SDK. The declared
[`asInvoker` execution level](https://learn.microsoft.com/en-us/windows/win32/sbscs/application-manifests#trustinfo)
uses the caller's execution level; standard-token launch remains a separate
qualification from execution on an administrative CI runner.

## Execute an author program

Use the [authoring guide](authoring-v2.md) for Zig/C/Starlark. Author functions,
conditions and module composition produce typed IR and an optional source map.
Starlark receives generic `--arg key=value` arguments. JSON files at the compiler
boundary are emitted IR and lock data; they contain no runtime author expressions.

A lock fixes the runtime, its metadata, libraries, content and host tools by version,
length and SHA-256. Runtime metadata is a separate dependency of the runtime entry.
Origins are provenance, not implicit resolution or authority.

## Assemble from published inputs

An assembly directory needs the host compiler, the host Component inspector,
selected target template/metadata, emitted product, lock, Components and content.
It needs a host signer when the selected native profile requires signing.

```sh
niobium-compiler-v2 compile \
  --program product.program.json --source-map product.sources.json \
  --lock inputs.lock.json \
  --runtime runtime --runtime-metadata runtime-metadata --worker worker \
  --input runtime=runtime-template \
  --input runtime-metadata=runtime-package.json \
  --input worker=niobium-component-worker \
  --input files=files.wasm --input content=content.tar \
  --signer signer --input signer=rcodesign \
  --output setup
```

Input IDs must match the product and lock; the example names are illustrative.
Omit the signer arguments for the current unsigned PE/ELF profile. Mach-O uses a
pinned host `rcodesign` tool, with archive identities in
[`third_party/apple_codesign/toolchain.zon`](../../third_party/apple_codesign/toolchain.zon).
The compiler copies and verifies inputs, closes writable executable handles before
launching tools, verifies final bytes and publishes atomically. An existing output
survives capture, validation, cancellation and signing failures.

Use a filesystem supported by the private access contract for the compiler's
workspace. Current qualification uses local filesystems, including Linux ext and
tmpfs. Shared virtiofs output was explicitly refused; qualification assembled on
local storage and transferred the final files with a digest comparison. This is a
filesystem qualification boundary, independent of the target OS and payload toolchain.

The pinned `rcodesign verify` command has an upstream ad-hoc verification limitation.
Niobium verifies its supported CodeDirectory measurements and native-prefix binding;
macOS qualification additionally runs `codesign --verify --strict` on the same bytes.
This does not establish publisher identity, Developer ID, Gatekeeper or notarization.

## Reproduce the isolated matrix

`zig build core-cross-tools compiler-linux-x64` builds the host fixture publisher,
Linux assembly witness and target-side lifecycle witnesses. Runtime publishers may
build the other native templates on their own hosts. The repository also provides
cross-build entrypoints when pinned target engine static libraries are supplied:

```sh
zig build runtime-linux-x64 \
  -Dcomponent-library-linux-x64=/published/linux/libniobium_wasmtime.a
zig build runtime-windows-x64 \
  -Dcomponent-library-windows-x64=/published/windows/libniobium_wasmtime.a
```

Those are runtime publication steps, separate from product assembly. Their engine
libraries must match the pinned Rust package/lock and profile. The local experiment
used Rust targets `x86_64-unknown-linux-musl` and `x86_64-pc-windows-gnu`, Zig C/AR/DLL
utilities and the same locked Cargo manifest. Rust's compiler wrapper must translate
its target triple to Zig's target spelling; this toolchain work does not enter the
product compiler.

The fixture publisher's positional interface is:

```text
core-cross-prepare OUTPUT_DIR LINUX_COMPILER MAC_RUNTIME WINDOWS_RUNTIME \
  LINUX_RUNTIME LINUX_WORKER LINUX_SIGNER FILES_COMPONENT CONSUMER_V1 \
  CONSUMER_V2 LINUX_ASSEMBLY_WITNESS
```

It runs author construction first, publishes inputs for all three targets and
writes model/lock files. Expose only that output directory read-only to an isolated
Linux x64 environment. Do not mount the repository. Record the container/image and
mount inventory, and verify that `zig`, `cargo`, `rustc`, `go`, `cc`, `gcc` and
`clang` are absent. Use a local writable output filesystem:

```sh
mkdir -p /tmp/outputs
/inputs/assemble /inputs /tmp/outputs
```

The witness runs the production compiler for two products and both consumer
releases, verifies each image and records compiler output. Record SHA-256 before
and after transferring the output files. A native x64 runner and x64 userspace
under Rosetta/emulation are different evidence contexts and must be labeled.

## Execute the delivered bytes

Build `core-cross-tools`, transfer the appropriate `core-delivered-*` witness and
the exact target output directory, then run from a writable local test directory:

```sh
core-delivered-native /published/aarch64-macos
core-delivered-linux-x64 /published/x86_64-linux
core-delivered-windows-x64.exe C:\published\x86_64-windows
```

Each command applies only to its target. The witness needs no checkout: it records
its own executable digest and must be archived with the external producer's source
and final-image ledger. It verifies real file contents and directories, optional
reconfiguration, fresh v2 state, explicit 1-to-2 migration, refusal without a path,
state/history and uninstall. `kernel-test` separately exercises every coordinator
kill boundary and repeated recovery with guest execution unavailable.

[Acceptance v0.3](../acceptance-plan-v0.3.md) distinguishes local native, emulated,
CI, filesystem and identity qualification. It also records what remains unrun.
