# Wasmtime Component Model qualification

- Upstream: https://github.com/bytecodealliance/wasmtime
- Version: `49.0.2`; license: Apache-2.0 WITH LLVM-exception.
- Source archive: https://codeload.github.com/bytecodealliance/wasmtime/tar.gz/refs/tags/v49.0.2
- Source SHA-256: `a260ed8947ea86996b0dd366aa42138dec02d4699268a7f01aa14e2e626e5639`.
- `adapter/Cargo.lock` pins every Rust dependency and registry checksum.
- Rust toolchain: `1.96.1`; the upstream minimum is `1.96.0`.

The adapter re-exports the official Component C API. Features are restricted to
`cranelift`, `component-model`, `pulley`, and `disable-logging`. The engine target
is explicitly `pulley64`; Cranelift prepares interpreter bytecode, not native
guest machine code. WASI, guest threads, async components, caching, and parallel
compilation are not enabled. Product-supplied serialized engine artifacts are
never deserialized.

`bindings.zig` declares the upstream C API without replacing the Canonical ABI.
`session.zig` owns its handles. The upstream `wasmparser` rejects automatic start
sections and provides parsed structures for the pre-compilation limits. The adapter
counts individual core recursive-group members and walks nested Component/core
module type declarations with an explicit depth bound; it does not equate a
section entry or recursive group with one type. `adapter/allocator.rs`
adds a worker-local Rust allocation quota. Its failure terminates the worker;
the journal parent must remain a separate process with a timeout and bounded
output. Guest linear memories and tables require separate store limits.

Wasmtime 49.0.2 assigns into C result slots and drops their prior values, despite
`component/func.h` saying their initial types are ignored. The wrapper initializes
each fresh output slot to `bool(false)` before calling the API. It does not patch
upstream. Callers must release previous results before reusing slots. The
qualification preserves the original failing invocation and checks actual typed
results through the wrapper.

Standard guest generation uses `wit-bindgen 0.61.1`, `wasm-tools 1.258.3`, Zig 0.17
and the WASI SDK 34 sysroot. [toolchain.zon](toolchain.zon) fixes source bytes.
Only the WASIp1 headers and static libc are extracted from that sysroot; no host
SDK executables or symlinks are installed. The C consumer links without startup
files and declares no WASI imports; the Rust consumer targets
`wasm32-unknown-unknown`. These are qualification consumers, not the product
capability interface.

The common `niobium:runtime/proposal@1.0.0` WIT package supplies resource-free
value types. Standard bindgen preserves these as type-only Component imports.
Production workers and the compiler use `program.wit.isTypeOnlyImport` to admit
nonempty value-only instances while rejecting nested resources, callable imports,
empty instances and the `wasi:` namespace. No native callback is registered for a
type-only dependency. The explicit `fact` callback belongs only to qualification.

The official files library and the independent reference library build as separate
Cargo packages from an isolated workspace containing the canonical WIT dependency.
Both use the same Component C API and worker. Their tests do not qualify a native
platform's installation or recovery behavior. See the
[SDK guide](../../docs/development/component-library-sdk.md) and
[version-two contract](../../docs/spec/capability-library-v2.md).

The native build selects an explicit Rust target from the Zig host OS and ABI;
it does not assume that rustup's default host matches the Zig linker. GNU targets
consume `libniobium_wasmtime.a`; MSVC consumes `niobium_wasmtime.lib`.

Native Rust static archives require the upstream platform libraries. GNU Windows
and Linux builds also link Zig's bundled unwind runtime. Native MSVC builds do
not receive the GNU unwind override. Platform execution evidence remains separate
from cross-compilation.
