---
title: '8. Compilation and diagnostics'
description: Follow author IR through locked inputs and native assembly, then diagnose type and content identity failures.
---

The compiler combines a typed product with exact locked inputs and a complete precompiled runtime. Binding diagnostics identify the stage and object that failed, with a source position when you supply the author's sidecar.

This chapter explains the build artifacts and reproduces two failures without changing an installation. Use the shell variables and macOS arm64 SDK from [Part I](/tutorial/setup/). Run commands from the Niobium checkout.

## Follow the build artifacts

| File in the prepared directory | Role |
|---|---|
| `product.star`, loaded `.star` modules | Author source, evaluated on the build host |
| `inputs.star` | Generated source constants containing actual identities and the runtime profile |
| `product.program.json` | Normalized author IR emitted by the frontend |
| `product.sources.json` | Optional source-map sidecar, separate from semantic model identity |
| `inputs.lock.json` | Exact source kinds, versions, lengths, digests and dependencies |
| `runtime`, `runtime-metadata` | Complete runtime template and independently locked publication metadata |
| `files` | Fixed official files Component |
| `content`, `fallback` | Canonical content containers prepared for this example |
| `worker`, `signer` | Locked inspection tool and, on macOS, final signing tool |
| `hello.setup` | Final native installer containing runtime, compiled product and payload |

The `.json` product is compiler transport, not a configuration file to write by hand. The compiler resolves complete WIT input types, validates authorities and dependencies, captures fixed inputs, normalizes content and assembles the image. It preserves the template's executable code rather than relinking or executing the target runtime.

Raw source bytes and canonical content have separate identities even when this example supplies an already canonical container. The runtime, metadata, library, compiled product and final installer also have separate identities. Digest agreement proves which bytes you have; trusted acquisition establishes who supplied them. This source-built exercise does not establish an external publisher's authority.

See [Compiler and frontends v2](https://github.com/niobium-project/niobium/blob/main/docs/spec/compiler-frontends.md) and [Locked compiler inputs](https://github.com/niobium-project/niobium/blob/main/docs/spec/compiler-inputs.md) for the full pipeline.

## Distinguish frontend and compiler errors

A malformed typed value can fail during author evaluation. For example, changing the baseline default to this expression produces `Error in value: bool required`:

```python
input("enabled", value("bool", "yes"))
```

Use `True`, rather than a string, to construct a boolean. The frontend includes the Starlark call position and does not emit a model for this evaluation failure.

A well-formed typed value can still have the wrong type for a library parameter. The next experiment constructs a string successfully, then fails when the compiler checks the binding against the library's `bool` field.

## Exercise: locate a use-site type error

Prepare independent inputs and change only the default's type:

```sh
DIAG_BUILD="$TUTORIAL_WORK/diagnostics"
"$NIOBIUM_REPO/zig-out/bin/niobium-tutorial-prepare" \
  --sdk "$NIOBIUM_REPO/zig-out" \
  --source "$NIOBIUM_REPO/examples/dsl-tutorial" --out "$DIAG_BUILD"
sed 's/input("enabled", value("bool", True))/input("enabled", value("string", "true"))/' \
  "$DIAG_BUILD/product.star" > "$DIAG_BUILD/bad-type.star"
"$NIOBIUM_REPO/zig-out/bin/nb-starlark-v2" \
  --source "$DIAG_BUILD/bad-type.star" \
  --out "$DIAG_BUILD/bad-type.program.json" \
  --source-map "$DIAG_BUILD/bad-type.sources.json"
```

Author evaluation succeeds. Compile that emitted model:

```sh
"$NIOBIUM_REPO/zig-out/bin/nb-builder" compile \
  --program "$DIAG_BUILD/bad-type.program.json" \
  --source-map "$DIAG_BUILD/bad-type.sources.json" \
  --lock "$DIAG_BUILD/inputs.lock.json" \
  --runtime runtime --runtime-metadata runtime-metadata --worker worker \
  --input "runtime=$DIAG_BUILD/runtime" \
  --input "runtime-metadata=$DIAG_BUILD/runtime-metadata" \
  --input "worker=$DIAG_BUILD/worker" --input "files=$DIAG_BUILD/files" \
  --input "content=$DIAG_BUILD/content" --input "fallback=$DIAG_BUILD/fallback" \
  --signer signer --input "signer=$DIAG_BUILD/signer" \
  --output "$DIAG_BUILD/hello.setup"
```

This command exits 1. Its diagnostic contains these fields, plus the actual position of the `deploy` call in `bad-type.star`:

```json
{
  "stage": "binding",
  "code": "type_mismatch",
  "object": "deploy",
  "kind": "call",
  "cause": "WitTypeMismatch"
}
```

The source points to the call whose argument failed WIT validation. Trace its `enabled` binding to the input default. The complete correction is the original declaration:

```python
input("enabled", value("bool", True))
```

The unmodified `product.star` already contains that answer. Emit it into fresh files, then build:

```sh
"$NIOBIUM_REPO/zig-out/bin/nb-starlark-v2" \
  --source "$DIAG_BUILD/product.star" \
  --out "$DIAG_BUILD/good.program.json" \
  --source-map "$DIAG_BUILD/good.sources.json"
"$NIOBIUM_REPO/zig-out/bin/nb-builder" compile \
  --program "$DIAG_BUILD/good.program.json" \
  --source-map "$DIAG_BUILD/good.sources.json" \
  --lock "$DIAG_BUILD/inputs.lock.json" \
  --runtime runtime --runtime-metadata runtime-metadata --worker worker \
  --input "runtime=$DIAG_BUILD/runtime" \
  --input "runtime-metadata=$DIAG_BUILD/runtime-metadata" \
  --input "worker=$DIAG_BUILD/worker" --input "files=$DIAG_BUILD/files" \
  --input "content=$DIAG_BUILD/content" --input "fallback=$DIAG_BUILD/fallback" \
  --signer signer --input "signer=$DIAG_BUILD/signer" \
  --output "$DIAG_BUILD/hello.setup"
```

The compiler exits 0 and prints a JSON report with `status="ok"`. Every locked input needs an `--input` mapping, including the prepared fallback even when the baseline does not use it.

## Exercise: preserve an existing output on failure

Save the valid installer and content, then change the content source without updating its lock:

```sh
cp "$DIAG_BUILD/hello.setup" "$DIAG_BUILD/hello.saved"
cp "$DIAG_BUILD/content" "$DIAG_BUILD/content.saved"
printf x >> "$DIAG_BUILD/content"
```

Run the successful compiler command above again, using `good.program.json` and the same output path. It now exits 1 and prints `error: LockMismatch`. This rejection happens while capturing inputs, before a detailed object diagnostic is populated; the JSON error report has `diagnostic: null`.

The complete recovery for this intentional experiment is:

```sh
cmp "$DIAG_BUILD/hello.saved" "$DIAG_BUILD/hello.setup"
cp "$DIAG_BUILD/content.saved" "$DIAG_BUILD/content"
cmp "$DIAG_BUILD/content.saved" "$DIAG_BUILD/content"
```

Both comparisons exit 0 with no output. The failed build preserves the previously published installer, and the source is restored. No runtime command ran, so the experiment does not change an installation. For a real content update, regenerate identities and the lock through preparation, then build a new release as in [Configure, update and remove](/tutorial/configure-update-remove/).

## Output ownership and compatibility

The preparation tool requires a new destination directory. The Starlark frontend creates its model and optional sidecar exclusively; use new filenames for another evaluation. If a filename already exists, choose a new name instead of treating the refusal as a language error. The compiler publishes an assembled image only after verification and required final signing; its publication can replace an existing installer.

The tutorial's content-only second release retains `model_version=1`, `Call.id="deploy"` and `state_version=1`, while increasing `release_sequence`. Model transitions and call-state transitions have independent compatibility declarations. Do not invent compatibility by incrementing a version or renaming a call. The [migration contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/migration.md) defines the advanced cases.

The supplied macOS finalizer covers the ad-hoc measurement profile. Production publisher signing and platform qualification require their own workflows and evidence; the tutorial's successful compilation does not establish them. See [Status and platforms](/status/) for the recorded scope.

Return to [the tutorial overview](/tutorial/) or use [Authoring v2](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring.md) to continue with the full API.
