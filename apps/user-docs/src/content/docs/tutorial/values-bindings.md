---
title: '5. Values, bindings and installation inputs'
description: Distinguish source values, exact WIT values, argument bindings, build parameters and installation inputs.
---

Use `value()` for typed data and `binding()` for the source of a call argument. A binding can preserve an installation-time choice even though the Starlark program has already finished.

This chapter explains the layers of values and the two kinds of inputs. Keep the shell and release 1 files from [Part I](/tutorial/setup/). All commands run from the Niobium checkout.

## Three layers of values

The `enabled` field in the tutorial passes through three layers:

| Layer | Example | Meaning |
|---|---|---|
| Starlark value | `True` | A boolean used while evaluating source |
| Typed product value | `value("bool", True)` | An exact boolean stored as the input default |
| Argument binding | `binding("input", "enabled")` | Read the selected input when evaluating the runtime graph |

Declare the default and bind the argument separately:

```python
input("enabled", value("bool", True))

# Inside the request record passed to files.build:
"enabled": binding("input", "enabled"),
```

Using `binding("literal", value("bool", True))` for that request field would always pass true, regardless of the selected input.

## Construct exact typed data

WebAssembly Interface Types (WIT) describe the parameters and results exported by a Component. Niobium preserves those types. Integer width matters: `u32` and `u64` are distinct even when both contain `1`.

These expressions are valid after `product()` has created the author context:

```python
enabled = value("bool", True)
length = value("u64", 10240)
title = value("string", "Hello")
format = value("enum", "posix-pax-v1")
digest = value("bytes", b"\x00" * 32)
content = value("record", {
    "format": format,
    "sha256": digest,
    "bytes": length,
})
```

The zero digest here demonstrates a byte value only. The runnable product uses `CONTENT_DIGEST` and `CONTENT_BYTES` generated from the actual canonical content. A hex string and the 32 raw digest bytes are different values.

Composite values contain typed values, rather than ordinary Starlark elements. For example, `value("list", [value("string", "Hello")])` is a typed list. The API also covers tuples, variants, options, results and flags; the constructor details live in [Authoring v2](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring-v2.md#starlark-api).

A typed record is fixed data. A record binding can combine different sources:

```python
request = binding("record", {
    "content": binding("literal", content),
    "enabled": binding("input", "enabled"),
})
```

This excerpt shows composition only. The files library's complete request also contains the root, grant, prefix and two access policies, as in `product.star`.

## Build parameters and installation inputs

`--arg` supplies immutable strings to the author. `--set` supplies scalar input values to the installer. The same spelling does not connect them automatically:

| Choice | When read | Effect |
|---|---|---|
| `--arg release_sequence=2` | Author evaluation | The tutorial converts the string with `int()` and emits release 2 |
| `--arg enabled=false` | Author evaluation | No effect, because `product.star` does not read this key |
| `--set enabled=false` | Installation or reconfiguration | The input binding passes false to `files.build` |

Verify the middle row without changing the installer:

```sh
"$NIOBIUM_REPO/zig-out/bin/niobium-starlark-v2" \
  --source "$TUTORIAL_WORK/release1/product.star" \
  --arg enabled=false --out "$TUTORIAL_WORK/values-args.program.json"
cmp "$TUTORIAL_WORK/release1/product.program.json" \
  "$TUTORIAL_WORK/values-args.program.json"
```

`cmp` exits 0 with no output. The author's emitted model still contains the true default.

## Exercise: keep the default, select false

Install release 1 with content disabled, then enable it without rebuilding. Use a separate root so this exercise does not modify the installation from Part I.

The complete solution is:

```sh
VALUES_ROOT="$TUTORIAL_WORK/values-installation"
mkdir "$VALUES_ROOT"
"$TUTORIAL_WORK/release1/setup" install \
  --root "application=$VALUES_ROOT" --set enabled=false
test ! -e "$VALUES_ROOT/current/hello/README.txt"
"$TUTORIAL_WORK/release1/setup" reconfigure \
  --root "application=$VALUES_ROOT" --set enabled=true
cmp "$NIOBIUM_REPO/examples/dsl-tutorial/payload/README.txt" \
  "$VALUES_ROOT/current/hello/README.txt"
"$TUTORIAL_WORK/release1/setup" uninstall \
  --root "application=$VALUES_ROOT"
```

The first check succeeds because false produces no desired content. The second succeeds because reconfiguration supplies true to the same compiled input binding. Neither operation evaluates Starlark.

## Defaults and complete input types

The compiler resolves an input's complete type from the actual WIT parameter wherever its binding is used. It checks the default and rejects conflicting uses. An enum's default case does not restrict its domain to that one case.

An unused boolean, integer or fully typed record can supply enough information for inference. An unused empty generic list, absent option, enum, flags, variant or result cannot. For example, `input("unused", value("list", []))` emits author IR but fails compilation with `InputTypeAmbiguous`. Bind such an input to a real typed parameter; do not invent a serialized type field. Input overrides and retained inputs are checked against the compiler-resolved type.

See [Parameter types](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring-v2.md#parameter-types) for the rules, and [Compilation and diagnostics](/tutorial/compilation-diagnostics/) for a type-error experiment.

Next: [Content, authority and capability calls](/tutorial/content-capabilities/).
