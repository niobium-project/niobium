---
title: '4. Syntax and build-time execution'
description: Use variables, collections, functions and conditions to construct a product before its installer runs.
---

You can use Starlark programming constructs to generate the product model. Their execution finishes during the build. The installed product contains the resulting typed graph, with no Starlark interpreter or author source evaluation.

This chapter teaches variables, collections, functions and conditional construction. Complete [the first installer](/tutorial/first-installer/) first. Run commands from the Niobium checkout in the same shell, keeping `NIOBIUM_REPO` and `TUTORIAL_WORK` from [the preparation chapter](/tutorial/setup/).

## Read the language

Starlark uses indentation for blocks. Strings use quotes, `True` and `False` are booleans, and `#` starts a comment. Assignments name values:

```python
prefix = "hello"
enabled = True
release_sequence = 1
```

The collections you need first are lists, tuples and dictionaries:

```python
names = ["cli", "examples"]
access = (rights(read=True, write=True), rights(read=True))
defaults = {"cli": True, "examples": False}
```

A list preserves element order; a dictionary maps keys to values. A tuple can group a fixed pair, as the grant's `(owner, everyone)` rights do. These are ordinary Starlark values. The next chapter explains how `value()` turns them into exact typed product values.

Functions begin with `def`. Put statement-form `if` and `for` inside a function; the current worker does not enable top-level conditional or loop statements.

```python
def default_enabled(include):
    if include:
        return value("bool", True)
    return value("bool", False)
```

Calling this function decides which boolean to place in the model. It does not create an installation-time condition.

## Construct several inputs

Create `$TUTORIAL_WORK/syntax.star` with this complete source:

```python
product(id="example.syntax", release_sequence=1, target="aarch64-macos",
        profile="niobium.user.component", primitives={})

def declare_inputs(names, defaults, include_docs):
    for name in names:
        input(name, value("bool", defaults[name]))
    if include_docs:
        input("docs", value("bool", True))

declare_inputs(["cli", "examples"], {"cli": True, "examples": False},
               args.get("docs", "false") == "true")
```

Evaluate it twice into fresh files:

```sh
"$NIOBIUM_REPO/zig-out/bin/niobium-starlark-v2" \
  --source "$TUTORIAL_WORK/syntax.star" \
  --out "$TUTORIAL_WORK/syntax.program.json"
"$NIOBIUM_REPO/zig-out/bin/niobium-starlark-v2" \
  --source "$TUTORIAL_WORK/syntax.star" --arg docs=true \
  --out "$TUTORIAL_WORK/syntax-docs.program.json"
cat "$TUTORIAL_WORK/syntax.program.json"
cat "$TUTORIAL_WORK/syntax-docs.program.json"
```

The first model declares `cli` and `examples`; the second also declares `docs`. Both commands exit successfully without installing anything. This small model demonstrates author evaluation only; it has no content or capability calls.

`args` is an immutable dictionary of strings populated by repeated `--arg KEY=VALUE`. The author owns the keys and their interpretation. Here, comparing the string with `"true"` produces the boolean passed to the function.

## Exercise: change a default

Make `examples` enabled by default without adding an input or changing its ID. Evaluate the source into `$TUTORIAL_WORK/syntax-answer.program.json` and inspect the `examples` input.

The complete solution is:

```python
product(id="example.syntax", release_sequence=1, target="aarch64-macos",
        profile="niobium.user.component", primitives={})

def declare_inputs(names, defaults, include_docs):
    for name in names:
        input(name, value("bool", defaults[name]))
    if include_docs:
        input("docs", value("bool", True))

declare_inputs(["cli", "examples"], {"cli": True, "examples": True},
               args.get("docs", "false") == "true")
```

Run the first evaluation command with the new output path. The emitted `examples` default is now true. The source's loop has completed; no loop remains for the installer to run.

## Keep build and installation separate

The worker exposes Starlark and Niobium author builtins. It does not expose Python imports, arbitrary filesystem access or shell execution. `load()` imports bounded source modules within the author root, which you will use in [Functions and modules](/tutorial/functions-modules/).

At installation time, input bindings and host observations supply values to fixed capability calls. Product behavior that must run then belongs to the capability library, such as the files library's choice to deploy content when `enabled` is true.

See [Authoring v2](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring-v2.md) for the author API and worker limits.

Next: [Values, bindings and installation inputs](/tutorial/values-bindings/).
