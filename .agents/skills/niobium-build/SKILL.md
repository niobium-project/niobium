---
name: niobium-build
description: Maintain this repository's zig build graph, public step names, subdirectory packages, pinned Rust and Go host tools, and the git hooks installed by zig build. Use when adding or renaming a zig build step, changing .zig/toolchains.zon, deciding whether a tool is installed by Zig or only reported when missing, or changing hooks:install, hooks:pre-commit, hooks:pre-push, or the commit-message check.
---

# Niobium build graph

[ADR-0027](../../../docs/adr/0027-zig-provisioned-host-tools.md) is the decision.
[Tooling](../../../docs/development/tooling-and-rules.md) lists the public steps.
`build/commands.zig` rejects a step that is not in that list.

## Add a step

1. Put the name in `build/commands.zig` and register it with `commands.step`.
2. Use a top-level name only for `fmt`, `lint`, `check`, `test`, `verify`, or `run`.
3. Otherwise use `namespace:leaf`. A second colon is only for a detail of that leaf, as in `example:tutorial:tools`.
4. Update the command in the owning doc, CI, and both READMEs in the same change. Do not keep the old name as an alias.

## Where the work lives

- Repository build and test steps stay in the root graph.
- `examples/hello` is a separate package. The root `example:hello` step only runs `zig build` there.
- `examples/dsl-tutorial` calls the root steps `example:tutorial` and `example:tutorial:tools`. Those steps stay in the root graph because they link its modules.

## Host tools

Pins live only in `.zig/toolchains.zon`. Official URLs and sha256 values. No private hosts.

`tools:install` and the build or test steps that run Cargo or Go use `.cache/tools`. They do not read a user-wide Rust or Go install.

Do not install tools for examples, the user-docs site, VM smoke, OS signing, or the Windows GNU `gcc` / `dlltool`. Those steps check for the program and, when it is absent, fail with its name and where to install it.

## Git hooks

Hook behavior belongs to `hooks:install`, `hooks:pre-commit`, `hooks:pre-push`, and `check:commits`. Platform wrappers live in `.githooks/posix` and `.githooks/windows` and only call those steps. Do not put a second policy in the wrappers. `zig build hooks:install` copies the host platform's wrappers into `.git/hooks`.
