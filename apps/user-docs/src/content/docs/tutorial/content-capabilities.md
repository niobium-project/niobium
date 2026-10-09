---
title: '6. Content, authority and capability calls'
description: Connect content identities, logical roots, access grants, Component calls, result dependencies and host observations.
---

A capability library proposes the product's desired resources. The host validates its content, authority and access policies before freezing a transaction. Declaring an archive or loading a library does not by itself authorize a machine change.

This chapter follows the tutorial's declarations, then adds a real result dependency and a host observation. Keep `NIOBIUM_REPO` and `TUTORIAL_WORK` from [Part I](/tutorial/setup/); commands use the verified macOS arm64 SDK from that part.

## Identify the objects

The product has a small set of independent objects:

| Declaration | Tutorial ID | Purpose |
|---|---|---|
| `root()` | `application` | Logical ownership anchor, bound to a native directory by `--root` |
| `state_root()` | `application` | Root coordinating durable installation state |
| `container()` | `content` | Fixed canonical content, identified by digest and byte length |
| `library()` | `files` | Fixed Component exporting the file deployment functions |
| `grant()` | `owned` | Authority and resource ceilings for `content.tree` on the root |
| `call()` | `deploy` | One instance of the library's `build` function |

The `member` values, such as `libs/files.wasm` and `content/hello.tar`, name members of the installer payload. They are not installation paths. The root and the request's `prefix="hello"` determine where the proposed `README.txt` goes.

The preparation tool encodes `payload/README.txt` as canonical POSIX pax content. `container()` declares its identity; the request's typed `content` record passes that same identity to the library. The compiler input lock separately fixes the source bytes used to assemble the installer. See the [content contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/content-container.md) for normalization and identity rules.

## Grant ceilings and desired access

The baseline grant permits bounded file deployment:

```python
access = (rights(read=True, write=True), rights(read=True))
grant(id="owned", root="application", primitive="content.tree", version=1,
      max_entries=16, max_bytes=1048576,
      file_access=access, directory_access=access)
```

`rights()` builds the grant's permission bits. The first tuple element is the owner's ceiling; the second is everyone's ceiling. The call receives this authority only because it declares `grants=["owned"]`.

The files library also receives an explicit desired policy, represented by a typed WIT record:

```python
owner = value("record", {
    "read": value("bool", True),
    "write": value("bool", True),
    "execute": value("bool", False),
})
everyone = value("record", {
    "read": value("bool", True),
    "write": value("bool", False),
    "execute": value("bool", False),
})
file_access = value("record", {
    "schema": value("u32", 1), "kind": value("enum", "file"),
    "owner": owner, "everyone": everyone,
})
```

The directory policy has `kind="directory"` and the same rights. Both appear in the request under the exact WIT field names `file-access` and `directory-access`. A desired policy must fit its grant's ceiling. Archive mode `0644` is content metadata; it does not grant installed access. Directory `execute` must be false in this portable policy. See [Portable access policy](https://github.com/niobium-project/niobium/blob/main/docs/spec/access-policy.md) for native mappings and rejection rules.

## Values and plans

The baseline uses a fixed function selector and requests a plan:

```python
call(id="deploy", library="files", interface="niobium:files/installer@1.0.0",
     function="build", arguments=[request], grants=["owned"],
     state_version=1, result_role="plan")
```

The [files WIT interface](https://github.com/niobium-project/niobium/blob/main/api/wit/files/files.wit) defines `build` as returning `result<plan, string>`. A successful plan proposes containers and optional private state; an error aborts evaluation. The host checks the proposals and freezes the operations. Recovery uses the durable plan without rerunning Starlark or the library.

A call with `result_role="value"`, the default, makes its typed result available to other calls. Referencing it with `binding("node_result", "source")` creates a dependency automatically. An `after=["source"]` declaration adds sequencing when no result binding expresses the dependency. References must exist, and cycles are rejected; source declaration order is not the runtime schedule.

## Read a host observation

An observation declares a versioned, read-only host function:

```python
observe(id="machine", primitive="machine.facts", version=1, function="facts")
```

The flow example binds the observed `os` record field to the deployment prefix:

```python
"prefix": binding("observation", "machine", fields=["os"]),
```

`fields` is an ordered projection path through record fields, not an expression string. The target used to assemble the installer is fixed at build time; this observation reads the machine when the runtime evaluates the graph. It produces `macos` in this walkthrough.

## Exercise: select fallback content

Use [the complete flow author](https://github.com/niobium-project/niobium/blob/main/examples/dsl-tutorial/product_flow.star). It declares both primary and fallback content, adds a `primary` input, and calls the files library's pure `select-content` export:

```python
call(id="source", library="files", interface="niobium:files/installer@1.0.0",
     function="select-content", arguments=[binding("literal", content),
     binding("literal", fallback), binding("input", "primary")])

# Inside deploy's complete request:
"content": binding("node_result", "source"),
"prefix": binding("observation", "machine", fields=["os"]),
```

Build this model in a fresh directory, using the unmodified repository sample:

```sh
FLOW_BUILD="$TUTORIAL_WORK/flow"
"$NIOBIUM_REPO/zig-out/bin/niobium-tutorial-prepare" \
  --sdk "$NIOBIUM_REPO/zig-out" \
  --source "$NIOBIUM_REPO/examples/dsl-tutorial" --out "$FLOW_BUILD"
"$NIOBIUM_REPO/zig-out/bin/nb-starlark-v2" \
  --source "$FLOW_BUILD/product_flow.star" \
  --out "$FLOW_BUILD/product.program.json" \
  --source-map "$FLOW_BUILD/product.sources.json"
"$NIOBIUM_REPO/zig-out/bin/nb-builder" compile \
  --program "$FLOW_BUILD/product.program.json" \
  --source-map "$FLOW_BUILD/product.sources.json" \
  --lock "$FLOW_BUILD/inputs.lock.json" \
  --runtime runtime --runtime-metadata runtime-metadata --worker worker \
  --input "runtime=$FLOW_BUILD/runtime" \
  --input "runtime-metadata=$FLOW_BUILD/runtime-metadata" \
  --input "worker=$FLOW_BUILD/worker" --input "files=$FLOW_BUILD/files" \
  --input "content=$FLOW_BUILD/content" --input "fallback=$FLOW_BUILD/fallback" \
  --signer signer --input "signer=$FLOW_BUILD/signer" \
  --output "$FLOW_BUILD/hello.setup"
```

Install with fallback selected. The complete solution continues:

```sh
FLOW_ROOT="$TUTORIAL_WORK/flow-installation"
mkdir "$FLOW_ROOT"
"$FLOW_BUILD/hello.setup" install \
  --root "application=$FLOW_ROOT" --set primary=false
cmp "$NIOBIUM_REPO/examples/dsl-tutorial/fallback/README.txt" \
  "$FLOW_ROOT/current/macos/README.txt"
"$FLOW_BUILD/hello.setup" reconfigure \
  --root "application=$FLOW_ROOT" --set primary=true
cmp "$NIOBIUM_REPO/examples/dsl-tutorial/payload/README.txt" \
  "$FLOW_ROOT/current/macos/README.txt"
"$FLOW_BUILD/hello.setup" uninstall --root "application=$FLOW_ROOT"
```

Both comparisons exit 0 with no output. The same installer selects two different content identities through the `source` result and reads its prefix from the host observation. Selection does not acquire arbitrary files: both containers are declared and embedded before installation.

This flow model uses a separate installation root because its graph differs from the baseline. Do not treat an edited graph with the same release sequence as a new release of an existing installation.

Next: [Functions and modules](/tutorial/functions-modules/).
