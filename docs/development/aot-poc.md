# Run the DSL/AOT PoC

This workflow builds products through Starlark and reuses one precompiled runtime.
It exercises the macOS arm64, user-scope, CLI profile. Run the commands from the
repository root with Zig 0.17.0, Go 1.25 or newer, and the host C toolchain.

## Build the toolchain

```sh
zig build aot:build --cache-poison=disallowed
poc_dir="$(mktemp -d /private/tmp/niobium-poc.XXXXXX)"
```

The runtime template, compiler, Starlark worker and native author examples are in
`zig-out/bin`. Precompiled capability examples are in `zig-out/lib/capabilities`.
The C authoring header is installed in `zig-out/include/compiler.h`.

## Compile two releases

The product source is `examples/aot/toolchain.star`. It uses the same authoring
ABI as the native Zig and C examples. Generated `.program` files are intermediate
compiler output.

```sh
for version in 1 2; do
  zig-out/bin/niobium-starlark \
    --source examples/aot/toolchain.star \
    --library "zig-out/lib/capabilities/env-v${version}.wasm" \
    --version "$version" \
    --out "$poc_dir/v${version}.program"
  zig-out/bin/niobium-compiler \
    --program "$poc_dir/v${version}.program" \
    --runtime zig-out/bin/niobium-runtime \
    --out "$poc_dir/setup-v${version}"
done
```

Both products consume the same runtime executable. Assembly fills its reserved
section and applies ad-hoc signing. Existing output paths are refused.

## Install, migrate and remove

```sh
"$poc_dir/setup-v1" install --root "$poc_dir/install" --set sdk=preview
cat "$poc_dir/install/current/toolchain.env"
"$poc_dir/setup-v2" apply --root "$poc_dir/install"
cat "$poc_dir/install/current/toolchain.env"
"$poc_dir/setup-v2" status --root "$poc_dir/install"
"$poc_dir/setup-v2" uninstall --root "$poc_dir/install"
```

The library generates the environment file from the selected input and machine
facts. Release 2 explicitly migrates state format 1 to 2 before planning. Status
reports the program identity, generation, resource inventory and migration
receipts. Uninstall removes recorded resources and preserves unregistered files.

The root must have an existing parent and be empty before its first ownership
claim. Host bookkeeping remains after uninstall. A conflicting retained
generation is reported explicitly rather than overwritten.

## Verify the complete boundary

```sh
zig build aot:test --cache-poison=disallowed
zig build aot:e2e --cache-poison=disallowed
```

The native suite compares Zig/C/Starlark output, denies repository and runtime
toolchain access during assembly, checks final binary signatures, and kills real
processes around transaction boundaries. Evidence is written under `.evidence/aot`.
`aot-test` adds schema/type conformance, Wasm budgets and ownership regressions.

The product section is limited to 1 MiB. Guest output and state have additional
bounds in `contracts.Limits`. Resource paths use printable ASCII. Publisher
signing, larger images, other platforms and machine scope have separate
[work packages](../roadmap-v0.2.md).
