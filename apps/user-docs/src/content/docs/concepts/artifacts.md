---
title: Content and artifact identities
description: Distinguish deployable content, capability libraries, runtime templates, and final installer bytes.
---

A compiled installer fixes several identities: its product model, runtime template, capability libraries, content containers, and final executable. Each identity describes its own bytes and compatibility contract.

The [DSL tutorial](/tutorial/) packages `README.txt` as content and invokes the official files capability library to request its deployment. A capability library is executable Wasm Component code; a content container is the logical tree of files to deploy.

## Logical content containers

The current content profile contains regular files, directories, and explicit relative symbolic links. A versioned POSIX pax profile defines its canonical uncompressed tar stream. Entry order, ordinary modes, file bytes, empty directories, and exact link text contribute to that stream's identity.

A `ContainerRef` records the format, SHA-256, and byte length of this canonical stream. Source locations, download hashes, and compressed transport bytes have separate identities. Two source archives do not acquire the same content identity merely because their filenames match.

The parser rejects unsafe names, escaping links, conflicting entries, unsupported archive features, and excessive sizes. Logical validation is followed by native target-name and filesystem checks during deployment. Parsing a valid container does not authorize a write to the machine.

Archive modes remain content metadata. Explicit requested access policies and [grants](/concepts/privilege/) control deployed access. The full representation and normalization rules are in the [content contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/content-container-v1.md).

## Locked inputs and final bytes

A compiler lock records exact versions, lengths, and SHA-256 identities for the runtime, runtime metadata, libraries, content, and build tools. The compiler verifies the supplied bytes and does not resolve a missing input to a replacement version.

The assembler copies a precompiled runtime template into the output image without executing or relinking it. Final signing changes the delivered image's identity. Qualification must identify those final bytes; a content digest or template digest alone does not authenticate a publisher.

The [compiler input contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/compiler-inputs-v1.md) owns locking. The [setup image contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/setup-image-v2.md) owns assembly and final-image measurements.

## Retained Portable Run { #portable-run }

<details data-pagefind-ignore>
<summary>Manifest-era Portable Run and offline bundles</summary>

This section describes the manifest-era v1 runtime. Its `setup run` command is separate from the Component-v2 tutorial installer.

A v1 deployable component has a `tar.zst` artifact containing `component.json` and `files/`. Portable Run resolves its release through the signed repository, extracts it into a per-user content-addressed cache, and runs a named entrypoint without creating an installation root:

```sh
setup run com.example.hello:runtime.main --repo repo -- --some-argument
```

The retained runtime reuses cached components by digest, removes entries unused for 30 days, and returns the program's exit code. Its [artifact reference](/reference/artifact-format/) and [CLI reference](/reference/setup-cli/) retain that scope.

A v1 offline bundle places `setup` beside a complete signed `repository/` directory. See the retained [publishing guide](/guides/publish-and-host/#ship-an-offline-bundle). The current tutorial packages its fixed inputs directly into the delivered installer.

</details>
