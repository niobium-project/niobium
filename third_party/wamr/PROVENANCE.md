# WAMR

- Upstream: https://github.com/bytecodealliance/wasm-micro-runtime
- Version: WAMR-2.4.5
- Source: https://codeload.github.com/bytecodealliance/wasm-micro-runtime/tar.gz/refs/tags/WAMR-2.4.5
- SHA-256: `1ab09d51099f276ca4a1d6629f6b589aab2bd0caa01445e05031a4bed22c199b`
- License: Apache-2.0 WITH LLVM-exception; fetched upstream `LICENSE`.
- Upstream sources are downloaded by the existing dependency fetch gate.

The runtime statically links the classic interpreter with instruction metering.
Fast interpreter, JIT, AOT, WASI, built-in libc, guest threads, shared memory,
SIMD, reference types, multi-module loading and hardware-bound-check mapping are
disabled. The host enforces the additional Core Wasm profile before loading.

`shared-instruction-budget.patch` changes upstream's per-entry local counter to
consume the execution environment's counter directly. It prevents budget renewal
between migration and planning, including nested bytecode calls. Regression tests
exercise repeated calls under one evaluation budget.

`table-alignment.patch` aligns table instances and the classic interpreter label
stack to native pointer alignment. It fixes UBSan failures observed during the
actual ReleaseSafe execution tests; undefined-behavior checks remain enabled.
The portable unaligned-access implementation is selected explicitly.

`host.c`, `host.h` and `bindings.zig` are Niobium-owned integration files. They
serialize WAMR global initialization, use a caller-owned fixed allocator pool,
validate guest memory, and expose only the three explicit host callbacks.
