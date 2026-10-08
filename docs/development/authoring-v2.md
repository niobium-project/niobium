# Develop a typed product author

Native Zig and the [authoring C ABI v2](../spec/authoring-c-abi-v2.md) construct the
same product model. The Starlark worker in
[apps/starlark/v2](../../apps/starlark/v2/main.go) calls that public C API. Author
programs run during the build; setup runtime processes consume compiled data.

## Native and C APIs

Use `compiler.author.Builder.init` with an explicit product identity, release,
model version and runtime profile. Add typed inputs, libraries, containers, roots,
grants, observations, calls and upgrade declarations. `stateRoot` selects the
owned logical root for installation state. `normalized` returns a validated model;
`emit` returns normalized machine IR for the shared compiler pipeline.

The [native example](../../tests/author/author.zig) constructs a record argument
from literals, selected inputs, an observation projection and previous state.
The [C example](../../tests/author/author.c) constructs the same model through
[compiler_v2.h](../../api/c/compiler_v2.h). It demonstrates copied views,
context-owned typed object handles and separately owned output buffers. Follow
the header's lifetime and numeric-tag rules when implementing a language SDK.

For a GNU Windows consumer of `zig build core-sdk`, use GNU ld 2.47 or newer
(or the pinned Zig/LLD toolchain) and link the published archive
with its [native system dependency](../spec/authoring-c-abi-v2.md#native-static-linkage):

```sh
gcc -Izig-out/include tests/author/author.c -Lzig-out/lib \
  -lniobium_compiler_v2 -lntdll -o author.exe
```

The Starlark CGO binding declares the same Windows link dependency. Its internal
Windows build uses the already-required Zig C compiler/linker through a
build-owned `CC` setting. Other builds keep their normal C compiler settings.
Installed Starlark binaries and product assembly do not require that C toolchain.

Public operations do not accept an author-supplied JSON program. The backend's
bounded internal cloning and serialized compiler output are implementation
mechanisms, not an author configuration language.

## Parameter types

Defaults are typed values, but some do not describe a complete parameter domain.
The compiler resolves each used input from its actual WIT parameter types and
rejects incompatible uses. Unused scalar/record defaults can be inferred when
every nested type is known. An unused empty list, `None`, enum, flags, variant or
result is ambiguous and is rejected. Bind it to an actual typed parameter rather
than adding a fabricated enum domain or an unchecked serialized type.

The compiled `resolved_type` is compiler-owned. Runtime input overrides and saved
inputs are checked against it independently of whether an input is consumed.
An explicit standard WIT Type author API is a follow-on SDK package; none of the
current constructors implicitly treats a default enum case as its only valid case.

## Source positions

Use `Builder.location("call:configure", .{ .file = "product.zig", .line = 42,
.column = 1 })` to associate a stable object with its source. `emitSourceMap`
returns the shared schema-1 diagnostic sidecar. C consumers use `nbc2_location`
and `nbc2_emit_source_map`. Source metadata has its own budget and cannot change
model identity or cache keys.

Starlark records the caller file/line/column from its interpreter call stack when
an entry is constructed. `--source-map FILE` writes a separate optional sidecar.
Pass that file to the compiler's source-map option to obtain diagnostics against
the actual author program. It is not embedded in the runtime semantic model.

## Starlark API

The worker uses the pinned `starlark-go` dependency in `apps/starlark/go.mod`.
Source and module reads are bounded; module loads stay relative to the author
root, detect cycles and use a fixed module/execution-step budget. Functions,
conditionals and module composition are normal Starlark semantics.

| Builtin | Purpose |
|---|---|
| `product` | Explicit identity, release, target, profile and primitive versions |
| `value(type, data, ...)` | Exact scalar or composite WIT-compatible host value |
| `binding(type, data, fields=...)` | Literal/reference/projection or typed aggregate argument |
| `input`, `library`, `container` | Typed inputs and fixed package members |
| `root`, `state_root`, `grant` | Logical ownership and access ceilings |
| `rights` | Positive read/write/execute intent for an access policy |
| `observe` | Typed, versioned host observation |
| `call` | Fixed library export and its typed dependency bindings |
| `migration`, `upgrade` | Explicit library-state or product-model transition |

Value types are `bool`, `u8/u16/u32/u64`, `s8/s16/s32/s64`, `f32/f64`, `char`,
`string`, `bytes`, `list`, `tuple`, `record`, `variant`, `enum`, `option`, `result`
and `flags`. Composite values contain previously constructed typed objects.
Variant uses `label`; result uses `success`; an omitted payload means none.

Binding types are `literal`, `input`, `node_result`, `observation`,
`previous_state`, `record`, `list`, `tuple` and `some`. Records map names to typed
bindings. Projection fields are ordered field names, not expression strings.
`grant` requires separate file and directory access pairs `(owner, everyone)`.
The complete runnable example is
[author.star](../../tests/author/author.star), with a loaded helper module.

## Run conformance

```sh
zig build author-v2-test --cache-poison=disallowed --summary all
```

The graph builds the static C ABI with Zig compiler runtime support, compiles its
independent C consumer, builds/tests Starlark through a native CGO launcher, and
runs all three reference authors against the actual reference Component digest
and length. It compares normalized bytes and writes evidence to
`.evidence/author-v2/`. The examples accept an explicit target and the parity lane
defaults to its qualified build host. Passing this lane does not qualify installation behavior on that target.

The generated Starlark executable accepts `--source FILE --out FILE`. Repeated
`--arg KEY=VALUE` options populate an immutable `args` dictionary;
products define their own keys. The reference example reads `library_sha256`,
`library_bytes` and an optional `target`. There are no product-specific launcher
flags. Argument count, individual size and aggregate size are bounded; duplicate
keys are rejected. Output creation is exclusive.

A language SDK must wrap this contract's ownership, diagnostics and exact types,
then use the same compiler backend for byte/type/profile checks. A successful
model emission is not proof that assembly, signing or execution passed. Use the
product end-to-end and recovery lanes for those claims.
