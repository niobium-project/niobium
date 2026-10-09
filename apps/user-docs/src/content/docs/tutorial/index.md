---
title: Learn the Niobium DSL
description: Write a Starlark product, build its installer, follow its lifecycle, and learn the authoring and compilation model.
---

Build an installer that deploys a `README.txt`, change its configuration, and update it to a second release. Then extend the same example to learn the language and compilation model.

The tutorial uses the runnable [DSL example](https://github.com/niobium-project/niobium/tree/main/examples/dsl-tutorial). It assumes basic programming experience and familiarity with shell commands. You do not need prior Starlark or Wasm experience.

## Learning path

Part I follows a product from its author source to installed files. Read these chapters in order and keep the same shell open:

1. [Prepare the tools and project](/tutorial/setup/): build the SDK and create a working copy of the example.
2. [Build your first installer](/tutorial/first-installer/): write a product, compile it, and inspect its installed file.
3. [Configure, update, and remove](/tutorial/configure-update-remove/): change an installation input, build a second release, and uninstall.

Part II explains how the declarations produce the compiled product:

4. [Syntax and build-time execution](/tutorial/syntax/): use ordinary Starlark variables, collections, conditions, and loops.
5. [Values, bindings, and inputs](/tutorial/values-bindings/): distinguish author values from values resolved during installation.
6. [Content, authority, and calls](/tutorial/content-capabilities/): connect content and capability libraries with explicit grants.
7. [Functions and modules](/tutorial/functions-modules/): organize a product with functions and `load`.
8. [Compilation and diagnostics](/tutorial/compilation-diagnostics/): inspect build outputs and fix author and input errors.

## Source, installer, and installation

An author program is a `.star` file containing Starlark code and Niobium declarations. The Starlark worker executes it at build time and emits a typed product model. The compiler packages that model with a precompiled native runtime, fixed capability libraries, and content.

```text
product.star + loaded modules + build arguments
                   |
          Starlark worker (build time)
                   |
        typed product + source map
                   |
     compiler + locked runtime, libraries, content
                   |
                  setup
                   |
      install / reconfigure / update / uninstall
                   |
           installation root/current/
```

The delivered `setup` executes the compiled product's capability calls. It does not execute the author program. A capability library is a Wasm Component that computes desired installation resources; the content container holds the files to deploy.

The product names a logical root, `application`. An invocation binds it to a physical directory. A grant bounds the content and access that a library may request there. The runtime validates those requests before publishing files.

## Tutorial profile

These chapters use the current experimental Component-v2 profile: a command-line installer, user-scope roots, and the official files capability library. The example uses one root and one content container.

The commands use a POSIX shell on macOS arm64. Mach-O assembly uses the SDK's locked ad-hoc signer. Production publisher identity, Gatekeeper, and notarization require separate qualification; see the [runtime assembly workflow](https://github.com/niobium-project/niobium/blob/main/docs/development/cross-host-builds.md).


Start with [Prepare the tools and project](/tutorial/setup/).
