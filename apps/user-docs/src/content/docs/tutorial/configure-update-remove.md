---
title: '3. Configure, update, and remove'
description: Reconfigure an installation input, build and apply a second release, then verify uninstall behavior.
---

Disable and restore the installed content, then update its message and uninstall. Continue from [Build your first installer](/tutorial/first-installer/), using the same shell and checkout root.

## Change an installation input

Set `enabled` to false on the installed release:

```sh
"$TUTORIAL_WORK/release1/setup" reconfigure \
  --root "application=$TUTORIAL_WORK/installation" --set enabled=false
test ! -e "$TUTORIAL_WORK/installation/current/hello/README.txt"
"$TUTORIAL_WORK/release1/setup" status \
  --root "application=$TUTORIAL_WORK/installation"
```

The `test` command exits successfully without output when the file is absent. The product remains installed: the files library returns an empty desired content set for `enabled=false`.

Restore the content:

```sh
"$TUTORIAL_WORK/release1/setup" reconfigure \
  --root "application=$TUTORIAL_WORK/installation" --set enabled=true
cat "$TUTORIAL_WORK/installation/current/hello/README.txt"
```

The file again contains the release 1 message. Reconfiguration uses the installed product release; it does not rerun the author program or build another installer.

## Build release 2

Change the payload in your source copy:

```sh
printf '%s\n' 'Hello from the Niobium DSL tutorial, release 2.' \
  > "$TUTORIAL_WORK/source/payload/README.txt"
```

Prepare a separate input set and execute the author with release sequence 2:

```sh
zig-out/bin/niobium-tutorial-prepare \
  --sdk "$NIOBIUM_REPO/zig-out" \
  --source "$TUTORIAL_WORK/source" \
  --out "$TUTORIAL_WORK/release2"
zig-out/bin/niobium-starlark-v2 \
  --source "$TUTORIAL_WORK/release2/product.star" \
  --out "$TUTORIAL_WORK/release2/product.program.json" \
  --source-map "$TUTORIAL_WORK/release2/product.sources.json" \
  --arg release_sequence=2
```

The prepare tool records the changed content's identity. `--arg release_sequence=2` changes the release number while retaining the product ID, model version, and call state version. Increasing the sequence orders this release after release 1.

Assemble the second installer:

```sh
zig-out/bin/niobium-compiler-v2 compile \
  --program "$TUTORIAL_WORK/release2/product.program.json" \
  --source-map "$TUTORIAL_WORK/release2/product.sources.json" \
  --lock "$TUTORIAL_WORK/release2/inputs.lock.json" \
  --runtime runtime --runtime-metadata runtime-metadata --worker worker \
  --input "runtime=$TUTORIAL_WORK/release2/runtime" \
  --input "runtime-metadata=$TUTORIAL_WORK/release2/runtime-metadata" \
  --input "worker=$TUTORIAL_WORK/release2/worker" \
  --input "files=$TUTORIAL_WORK/release2/files" \
  --input "content=$TUTORIAL_WORK/release2/content" \
  --input "fallback=$TUTORIAL_WORK/release2/fallback" \
  --signer signer --input "signer=$TUTORIAL_WORK/release2/signer" \
  --output "$TUTORIAL_WORK/release2/setup"
```

Both installers remain available in their release directories. Release 2 embeds the new message; it does not fetch an update from a channel or repository.

## Apply the update

Run the new installer against the existing installation:

```sh
"$TUTORIAL_WORK/release2/setup" update \
  --root "application=$TUTORIAL_WORK/installation"
"$TUTORIAL_WORK/release2/setup" status \
  --root "application=$TUTORIAL_WORK/installation"
cat "$TUTORIAL_WORK/installation/current/hello/README.txt"
```

The file reads:

```text
Hello from the Niobium DSL tutorial, release 2.
```

The root mapping remains the same. The runtime publishes a generation containing the new content and persists the new release. The [migration contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/migration-v2.md) defines separate rules for changes to model and call state versions.

## Uninstall and check the result

Use the release 2 installer:

```sh
"$TUTORIAL_WORK/release2/setup" uninstall \
  --root "application=$TUTORIAL_WORK/installation"
test ! -e "$TUTORIAL_WORK/installation/current"
test ! -e "$TUTORIAL_WORK/installation/.niobium-v2/installation.json"
"$TUTORIAL_WORK/release2/setup" status \
  --root "application=$TUTORIAL_WORK/installation"
```

The two `test` commands exit successfully without output. Uninstall removes the published content and active installation snapshot. Ownership records and verified content storage may remain under `.niobium-v2/`; uninstall does not promise to delete the entire root.

The runtime removes managed resources only when their contents and native identity still match its recorded inventory. Keep tutorial files unchanged when checking this result. Modified or unknown files can remain in retired generations.

## Exercise: choose the phase

Choose the operation for each change: hide the installed file, change its text, or change the product's release sequence.

Use `reconfigure --set enabled=false` to hide the file. To change its text, edit the source payload and prepare a new content container. Supply a larger `--arg release_sequence` when executing the author, then compile and apply the new installer.

Next: [Syntax and build-time execution](/tutorial/syntax/).
