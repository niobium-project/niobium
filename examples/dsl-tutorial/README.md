# DSL tutorial example

Follow the [user tutorial](../../apps/user-docs/src/content/docs/tutorial/index.md)
to build, install, configure, update and remove this Starlark product.

`product.star` installs `payload/README.txt` through the official files Component.
`product_modular.star` and `model.star` construct the same model using a loaded
function. `product_flow.star` selects between the primary and fallback content
and uses a host observation to choose its installation prefix.

## Prepare and verify

Build the published host SDK and the example's preparation tool from the
repository root:

```sh
zig build core-sdk dsl-tutorial-tools --cache-poison=disallowed
```

The tool accepts `--sdk DIR --source DIR --out DIR`. It copies the SDK inputs and
author files, writes canonical content containers, and generates `inputs.star`
and `inputs.lock.json` in a new output directory. It does not execute the author
program or compile an installer. Use the tutorial's separate commands for those
steps, including all locked inputs and the signer required on macOS.

Run the example's native lifecycle and diagnostic checks:

```sh
zig build dsl-tutorial-test --cache-poison=disallowed
```

Evidence is written to `.evidence/dsl-tutorial/`. Results describe the actual
build host and do not establish execution qualification on another platform.
