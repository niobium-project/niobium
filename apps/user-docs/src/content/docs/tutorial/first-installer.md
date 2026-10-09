---
title: '2. Build your first installer'
description: Read a complete Starlark product, emit its typed model, assemble an installer, and check the deployed file.
---

Compile the example into `setup`, install it into an empty directory, and read its `README.txt`. Continue from [Prepare the tools and project](/tutorial/setup/), using the same shell and checkout root.

## Read the product

Open `$TUTORIAL_WORK/source/product.star`. This is the complete author program:

```python
load("inputs.star", "TARGET", "PROFILE", "PRIMITIVES", "FILES_SHA256", "FILES_BYTES",
     "CONTENT_SHA256", "CONTENT_DIGEST", "CONTENT_BYTES")

product(id="example.tutorial", release_sequence=int(args.get("release_sequence", "1")),
        model_version=1, target=TARGET, profile=PROFILE, primitives=PRIMITIVES)
root("application", scope="user")
state_root("application")
library(id="files", member="libs/files.wasm", sha256=FILES_SHA256, bytes=FILES_BYTES)
container(id="content", member="content/hello.tar", sha256=CONTENT_SHA256, bytes=CONTENT_BYTES)
input("enabled", value("bool", True))
access = (rights(read=True, write=True), rights(read=True))
grant(id="owned", root="application", primitive="content.tree", version=1,
      max_entries=16, max_bytes=1048576, file_access=access, directory_access=access)

owner = value("record", {"read": value("bool", True), "write": value("bool", True),
                         "execute": value("bool", False)})
everyone = value("record", {"read": value("bool", True), "write": value("bool", False),
                            "execute": value("bool", False)})
file_access = value("record", {"schema": value("u32", 1), "kind": value("enum", "file"),
                               "owner": owner, "everyone": everyone})
directory_access = value("record", {
    "schema": value("u32", 1), "kind": value("enum", "directory"),
    "owner": owner, "everyone": everyone,
})
content = value("record", {"format": value("enum", "posix-pax-v1"),
                           "sha256": value("bytes", CONTENT_DIGEST),
                           "bytes": value("u64", CONTENT_BYTES)})
request = binding("record", {
    "root": binding("literal", value("string", "application")),
    "grant": binding("literal", value("string", "owned")),
    "prefix": binding("literal", value("string", "hello")),
    "content": binding("literal", content),
    "enabled": binding("input", "enabled"),
    "file-access": binding("literal", file_access),
    "directory-access": binding("literal", directory_access),
})
call(id="deploy", library="files", interface="niobium:files/installer@1.0.0",
     function="build", arguments=[request], grants=["owned"], state_version=1,
     result_role="plan")
```

Read it in four groups:

1. `load` imports the generated input identities. `product` fixes the product ID, release sequence, model version, and runtime profile.
2. `library` names executable capability code. `container` names the packaged content. Their `member` paths identify entries inside the delivered image.
3. `root` names a user-scope installation root. `state_root` selects the root that coordinates installation state. `grant` bounds the library's content and access requests.
4. `request` binds the library argument fields. `call` selects the library's fixed `build` export and marks its result as a desired installation plan.

The `enabled` input defaults to true. Its binding makes it an installation-time choice. The release sequence comes from `args`, which the Starlark worker receives at build time.

The access records request owner read/write and everyone read access. The grant supplies the corresponding ceilings. Part II explains [values and bindings](/tutorial/values-bindings/) and [content authority](/tutorial/content-capabilities/) in detail.

## Execute the author program

The prepare tool copied this source into release 1 alongside its generated `inputs.star`. Execute that copy:

```sh
zig-out/bin/nb-starlark-v2 \
  --source "$TUTORIAL_WORK/release1/product.star" \
  --out "$TUTORIAL_WORK/release1/product.program.json" \
  --source-map "$TUTORIAL_WORK/release1/product.sources.json" \
  --arg release_sequence=1
```

`product.program.json` is emitted machine data. `product.sources.json` maps declarations back to source locations for diagnostics. The worker creates these outputs exclusively; use fresh output names when repeating the command.

## Assemble the installer

Pass the emitted model and the locked input files to the compiler:

```sh
zig-out/bin/nb-builder compile \
  --program "$TUTORIAL_WORK/release1/product.program.json" \
  --source-map "$TUTORIAL_WORK/release1/product.sources.json" \
  --lock "$TUTORIAL_WORK/release1/inputs.lock.json" \
  --runtime runtime --runtime-metadata runtime-metadata --worker worker \
  --input "runtime=$TUTORIAL_WORK/release1/runtime" \
  --input "runtime-metadata=$TUTORIAL_WORK/release1/runtime-metadata" \
  --input "worker=$TUTORIAL_WORK/release1/worker" \
  --input "files=$TUTORIAL_WORK/release1/files" \
  --input "content=$TUTORIAL_WORK/release1/content" \
  --input "fallback=$TUTORIAL_WORK/release1/fallback" \
  --signer signer --input "signer=$TUTORIAL_WORK/release1/signer" \
  --output "$TUTORIAL_WORK/release1/setup"
```

The compiler verifies the captured inputs against the lock, validates the capability interface and argument types, and packages the precompiled runtime. On macOS, the locked signer signs the final image bytes.

This command uses the macOS runtime prepared in chapter 1. The current PE/ELF assembly profiles omit the two signer options; using those profiles requires their target-specific runtime inputs and separate execution qualification.

## Install and inspect the file

Create an empty directory dedicated to this product:

```sh
mkdir "$TUTORIAL_WORK/installation"
"$TUTORIAL_WORK/release1/setup" install \
  --root "application=$TUTORIAL_WORK/installation"
"$TUTORIAL_WORK/release1/setup" status \
  --root "application=$TUTORIAL_WORK/installation"
cat "$TUTORIAL_WORK/installation/current/hello/README.txt"
```

The file reads:

```text
Hello from the Niobium DSL tutorial, release 1.
```

The product declares the logical name `application`; `--root` supplies its absolute physical path. The runtime claims only an absent or empty unowned root, so use the dedicated tutorial directory.

`current` points to the published generation's content. Its `hello` prefix comes from the library request. The runtime stores ownership and transaction data separately under `.niobium-v2/`; the [lifecycle contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/runtime-lifecycle.md) owns that layout.

## Exercise: find the installed path

Which declaration would change `current/hello/README.txt` to `current/docs/README.txt`?

Change the request's `prefix` literal from `hello` to `docs`. The root ID still selects the deployment root, while the content container still supplies `README.txt`. Try source changes in a fresh build directory and installation root.

Next: [Configure, update, and remove](/tutorial/configure-update-remove/).
