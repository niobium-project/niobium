# Develop a Component capability library

Use WIT and standard `wit-bindgen` to build a Component for
[capability library v2](../spec/capability-library-v2.md). The
[official files library](../../libs/stdlib/files/guest.rs) and the
[independent reference consumer](../../tests/component/reference/guest.rs) are
separate examples of the same public contract.

## Build the examples

The repository build requires Zig 0.17.0, Cargo with Rust 1.96.1, and its
`wasm32-unknown-unknown` target. It explicitly selects `cargo +1.96.1`; it does
not change the user's default Rust toolchain. The checked dependency fetcher
obtains the exact tools listed in
[toolchain.zon](../../third_party/wasmtime/toolchain.zon).

```sh
zig build component-test --cache-poison=disallowed --summary all
```

The build stages each Rust consumer into an isolated Cargo/WIT workspace. It copies
the owning WIT file and the canonical versioned dependency from
[api/wit/runtime](../../api/wit/runtime/proposal.wit) into `wit/deps/runtime`.
The common contract is not duplicated in source directories. Invoking Cargo
against the unstaged consumer source directly does not provide that WIT workspace.

The Rust consumers use `wit_bindgen::generate!` with an explicit `with: generate`
mapping for the shared package, then `export!` the implementation. The build uses
`wasm-tools component new --merge-imports-based-on-semver=false` on the resulting
core module. Rust dependencies and checksums are fixed by each Cargo lockfile.

The independent C qualification consumer uses the official generated C bindings,
Zig's Wasm C compiler and the pinned WASI SDK sysroot's headers/static libc. It
links without startup files and imports no WASI functions. Linking a reactor's
automatic startup section would violate this Component profile.

## Design the interface

Define a versioned WIT package and ordinary typed function signatures. Records,
variants and exact-width integers remain typed through compiler validation,
worker calls and state. Prefer a record for a cohesive request; author bindings
can construct records from literals, runtime inputs, observations and prior state.
There is no need to flatten a real API because it crosses a compiler boundary.

Reuse the shared desired-container and access types. Return a fixed reference for
existing content or generated entries for computed files. The host validates and
freezes both. Keep component selection, layout and dependency remediation policy
inside the library or its author-facing preset. Do not turn policy into a new
kernel enum or an unrestricted process import.

The reference consumer builds distinct default and `revision-two` artifacts. The
second artifact initializes revision-two state on a fresh install, rejects an
unconverted revision-one state and exposes the explicit converter. Both keep the
same WIT interface and call lineage.

A library may define its own private-state type. Its migration function accepts
the previous typed state and returns the next typed state; the compiled product
pins the transition, implementation digest and source/target versions. State and
resource handles are different concepts. Transient engine resources cannot be
stored in journals or passed between disposable workers.

Shared WIT packages introduce type-only imports. These are checked structurally,
including every nested type, by the same compiler/worker helper. They do not grant
host calls. Production machine observations currently arrive as prebound typed
arguments. The callback in `tests/component/worker.zig` is an engine qualification
fixture, not a production service available to arbitrary guests.

## Check behavior and failures

The suite runs C/Rust type and resource cases, type reflection, guest errors,
fuel/memory/output limits, allocator amplification, automatic-start refusal and
unauthorized imports. Production IPC exercises exact u64 values, named record
ordering, migrations, fixed and generated content, digest mismatch and resource
handle refusal. Evidence directories include the actual tested identities.

When adding a primitive, follow the
[capability development skill](../../.agents/skills/niobium-platform-capability/SKILL.md).
A new import needs a versioned permission contract, native implementation,
ownership rules and recovery semantics. A successful Wasm build does not establish
that the primitive or a target platform is qualified.

## Deploy executables and data with different access

Current desired-container access applies uniformly to each object kind in that
container. Archive modes remain content metadata; they do not grant execution or
restore host permissions. Partition a mixed tree at build time by desired policy:

| Fixed container | Logical entries | Desired file access | Desired directory access |
|---|---|---|---|
| `executables` | `bin/tool` | Owner read/write/execute; everyone read | Owner list/manage; everyone list |
| `data` | `share/defaults.toml` | Owner read/write; everyone read | Owner list/manage; everyone list |

Keep original relative paths in both canonical containers and deploy them to the
same logical root. Shared directories may coalesce only under equal controlled
directory policy. Conflicting file ownership or unequal directory policy is an
error. Neither source tar mode nor the author's build-host ACL decides the target
access policy.

A Starlark author can construct the two calls with this reusable helper. Here
`files` is the locked official library and `executable_ref` / `data_ref` are typed
content-reference values obtained from the product's fixed build inputs.

```python
def rights_value(execute):
    return value("record", {
        "read": value("bool", True),
        "write": value("bool", True),
        "execute": value("bool", execute),
    })

def policy(kind, execute):
    return value("record", {
        "schema": value("u32", 1),
        "kind": value("enum", kind),
        "owner": rights_value(execute),
        "everyone": value("record", {
            "read": value("bool", True), "write": value("bool", False),
            "execute": value("bool", False),
        }),
    })

def deploy(id, content, execute):
    grant(id=id, root="application", primitive="content.tree", version=1,
          max_entries=64, max_bytes=1048576,
          file_access=(rights(read=True, write=True, execute=execute), rights(read=True)),
          directory_access=(rights(read=True, write=True), rights(read=True)))
    request = value("record", {
        "root": value("string", "application"), "grant": value("string", id),
        "prefix": value("string", ""), "content": content,
        "enabled": value("bool", True),
        "file-access": policy("file", execute),
        "directory-access": policy("directory", False),
    })
    call(id=id, library="files", interface="niobium:files/installer@1.0.0",
         function="build", arguments=[binding("literal", request)],
         grants=[id], result_role="plan")

deploy("tools", executable_ref, True)
deploy("data", data_ref, False)
```

Qualify the assembled product on its declared OS/scope, including actual execute
access and recovery. This recipe does not establish support for all application
bundle metadata, native signing identities or macOS notarization.

A later per-entry access work package must define versioned, bounded typed entries;
explicit matching and duplicate/conflict rules; ownership and grant ceilings;
platform lowering; and durable permission transitions with crash recovery. It
must test mixed files/directories, symlinks, inherited ACLs and user modifications.
It must not infer authority from archive mode or introduce a kernel policy that
automatically translates tar RWX bits.
