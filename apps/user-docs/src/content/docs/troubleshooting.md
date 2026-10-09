---
title: Troubleshooting and FAQ
description: Diagnose current DSL compilation and maintenance errors.
tableOfContents:
  maxHeadingLevel: 2
---

## Compiler diagnostics

For the current DSL, begin with [compilation and diagnostics](/tutorial/compilation-diagnostics/).
The Starlark frontend produces a source map; compiler diagnostic JSON on stderr identifies
binding and type errors at the author source when a mapped diagnostic is available.
A locked-input capture failure can report `LockMismatch` with `diagnostic: null`.
Check the actual error and command stage before looking for a source location.

The tutorial demonstrates both failures and verifies that a failed compile preserves
an existing setup. Compiler diagnostics describe build-time errors; the retained
`nbpack` exit-code table below applies to a separate interface.

## Runtime maintenance

Use the same complete `--root` mapping for install and later maintenance. Runtime
`--set` binds declared installation inputs; Starlark `--arg` changes build-time author
arguments. [Values and bindings](/tutorial/values-bindings/) explains that distinction.

`KernelBusy` means a cooperating maintenance operation holds a root lock. Let it
finish before retrying. Every invocation, including `status`, can finish a compatible
pending transaction from its frozen plan. Preserve the ownership, plan, and receipt
files when reporting a failure; deleting them can prevent safe recovery.

The [lifecycle contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/runtime-lifecycle.md)
owns recovery and compatibility checks. The tutorial's
[configuration and update steps](/tutorial/configure-update-remove/) use the current CLI.
