---
title: '1. Prepare the tools and project'
description: Build the current SDK and prepare a separate working directory for the Starlark tutorial.
---

Build the authoring and compiler tools, then prepare the example's locked inputs. At the end of this chapter, you have a working copy of the source and a build directory for release 1.

## Prerequisites

Use macOS arm64 with a POSIX shell, Git, and Zig 0.17.0. The first SDK build
needs network access. Zig installs the pinned Rust and Go tools used to publish
the SDK. Compiling an already prepared product does not need them.

The [SDK build workflow](https://github.com/niobium-project/niobium/blob/main/docs/development/cross-host-builds.md) owns the native-target requirements.

## Build the SDK

Clone the repository, or use an existing checkout:

```sh
git clone https://github.com/niobium-project/niobium
cd niobium
```

Run all remaining commands in Part I from this checkout's root. Keep the shell open so the directory variables remain available:

```sh
NIOBIUM_REPO="$PWD"
zig build core:sdk example:tutorial:tools --cache-poison=disallowed
```

The SDK installs the Starlark worker, compiler, native runtime template, Component worker, and official files library under `zig-out/`. The tutorial build adds `zig-out/bin/niobium-tutorial-prepare`.

## Prepare a working copy

Create a separate directory and copy the tutorial project into it:

```sh
TUTORIAL_WORK="$(mktemp -d /tmp/niobium-tutorial.XXXXXX)"
cp -R examples/dsl-tutorial "$TUTORIAL_WORK/source"
```

The project contains `product.star`, its modular alternative, and `payload/README.txt`. Change files in this copy during the tutorial so the repository example remains available for comparison.

Prepare release 1:

```sh
zig-out/bin/niobium-tutorial-prepare \
  --sdk "$NIOBIUM_REPO/zig-out" \
  --source "$TUTORIAL_WORK/source" \
  --out "$TUTORIAL_WORK/release1"
```

The prepare tool creates a content container from `payload/README.txt`, captures the SDK inputs, and writes their exact lengths and SHA-256 identities into the lock. It also generates `inputs.star`, which supplies those identities to the author program.

Inspect the directory:

```sh
ls "$TUTORIAL_WORK/release1"
cat "$TUTORIAL_WORK/source/payload/README.txt"
```

The directory contains copied author source, `inputs.star`, `inputs.lock.json`, the runtime and its metadata, the Component worker, the files Component, and the content container. It also contains a small `fallback` content container for the chapter 6 exercise. On macOS it contains the locked signer.

Treat this directory as one release's inputs. Prepare release 2 into another directory when its content changes; the first directory remains the input set for release 1.

## Exercise: locate the source and output

Identify the file you edit to change the installed message and the file you edit to change the product declarations.

The message comes from `$TUTORIAL_WORK/source/payload/README.txt`. The declarations come from `$TUTORIAL_WORK/source/product.star`. `inputs.star` and `inputs.lock.json` are generated build inputs; keep their recorded identities aligned with the captured bytes.

Next: [Build your first installer](/tutorial/first-installer/).
