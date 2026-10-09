---
title: '7. Functions and modules'
description: Organize author code with helper functions and load statements while preserving the normalized product model.
---

You can move product construction into functions and modules without changing the installer model. Compare emitted bytes to check that an organizational edit preserves behavior.

This chapter extracts the tutorial product into a module and verifies equivalence. It uses the prepared release 1 directory and the shell variables from [Part I](/tutorial/setup/). Commands run from the Niobium checkout.

## Use functions for source repetition

A helper function can construct a frequently used binding:

```python
def literal_string(text):
    return binding("literal", value("string", text))
```

In a request record, these expressions are equivalent:

```python
"root": binding("literal", value("string", "application")),
"root": literal_string("application"),
```

Choose one expression for the field; do not declare the key twice. The function runs while authoring and returns a typed binding. It is not stored as a function inside the model.

Creating typed values requires an existing product context. Define helpers first if convenient, but call `product()` before a helper constructs a `value()` or `binding()`. The product itself must be created exactly once.

## Move construction into a module

The prepared directory already contains this complete alternative entrypoint, `product_modular.star`:

```python
load("model.star", "make_product")

make_product(int(args.get("release_sequence", "1")))
```

The [complete `model.star`](https://github.com/niobium-project/niobium/blob/main/examples/dsl-tutorial/model.star) contains the baseline declarations inside `make_product(release_sequence)`. It loads the generated identity constants at module scope, then constructs the product when the entrypoint calls the function:

```python
load("inputs.star", "TARGET", "PROFILE", "PRIMITIVES", "FILES_SHA256", "FILES_BYTES",
     "CONTENT_SHA256", "CONTENT_DIGEST", "CONTENT_BYTES")

def make_product(release_sequence):
    product(id="example.tutorial", release_sequence=release_sequence,
            model_version=1, target=TARGET, profile=PROFILE, primitives=PRIMITIVES)
    root("application", scope="user")
    state_root("application")
    # The remaining declarations are in the complete module.
```

`load("model.star", "make_product")` imports the named symbol. It does not invoke the function. Keeping construction inside the function avoids creating the product as a side effect of importing the module.

The author root is the directory containing the entrypoint supplied to `--source`. Module paths are relative to that root, including loads performed by nested modules. They do not change to the loading module's own directory. For example, an entrypoint in `release1/` loads `lib/policy.star` from `release1/lib/policy.star`; a load inside that module still starts from `release1/`.

Loaded module globals are frozen by Starlark. Export functions and immutable data rather than depending on mutations of a shared dictionary after import. The worker caches modules within one evaluation and rejects load cycles, absolute paths and paths that lexically escape the author root. Its module and execution budgets are documented in [Authoring v2](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring-v2.md#starlark-api).

## Exercise: verify the extraction

Evaluate the flat and modular authors from the same prepared inputs and compare their normalized output. Do not change a release sequence, default, grant or content identity during this exercise.

The complete solution uses the supplied `product_modular.star` and `model.star`:

```sh
"$NIOBIUM_REPO/zig-out/bin/niobium-starlark-v2" \
  --source "$TUTORIAL_WORK/release1/product.star" \
  --out "$TUTORIAL_WORK/flat.program.json" \
  --source-map "$TUTORIAL_WORK/flat.sources.json"
"$NIOBIUM_REPO/zig-out/bin/niobium-starlark-v2" \
  --source "$TUTORIAL_WORK/release1/product_modular.star" \
  --out "$TUTORIAL_WORK/modular.program.json" \
  --source-map "$TUTORIAL_WORK/modular.sources.json"
cmp "$TUTORIAL_WORK/flat.program.json" "$TUTORIAL_WORK/modular.program.json"
cat "$TUTORIAL_WORK/modular.sources.json"
```

`cmp` exits 0 with no output. The sidecar associates declarations such as `call:deploy` with positions in `model.star`, so their diagnostic locations differ from the flat author. Source positions are separate from normalized model bytes and cannot change product identity.

If the comparison fails, compare the declarations before compiling an installer. A changed default or function argument is a model change, even if it happened during a source cleanup.

## Choose stable boundaries

Use functions for repeated construction and modules for coherent groups of author code. Module filenames organize source. The product identity, `Call.id`, `Library.id` and the interface/function selector identify runtime ownership. Moving `deploy` into another file preserves its ID. Renaming that call changes the owning instance and is not an equivalent refactor.

The [compiled product contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/program-image-v2.md#state-and-explicit-migration) defines call state ownership and explicit migration. Keep those changes separate from this byte-preserving source extraction.

Next: [Compilation and diagnostics](/tutorial/compilation-diagnostics/).
