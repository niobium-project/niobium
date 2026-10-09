# ADR-0027: Zig-provisioned Rust and Go for build and test

- **Status:** Accepted
- **Date:** 2026-10-09
- **Amends:** [ADR-0001](0001-repository-baseline-and-zig-only-toolchain.md) (contributor toolchain)

## Context

[ADR-0001](0001-repository-baseline-and-zig-only-toolchain.md) makes `zig build`
the entry point and says a new contributor needs Zig 0.17.0. Build and test
steps still invoked `cargo +1.96.1` and `go` from the developer `PATH`. Those
tools are not part of the product runtime. Isolated product assembly still runs
without them.

Rust 1.96.1 builds the Component engine and wasm32 guests. Go 1.26.8 builds the
Starlark worker. Node.js stays a host tool for the user-docs site
([ADR-0015](0015-node-toolchain-for-user-docs.md)). Example packages, target witnesses,
OS signing tools, and the Windows GNU publisher's `gcc` and `dlltool` are not
downloaded by the build.

## Decision

1. A development machine needs Zig 0.17.0. `zig build tools:install` materializes
   Rust 1.96.1 and Go 1.26.8 under `.cache/tools` from the pins in
   `.zig/toolchains.zon`. The pins are official public archives with sha256
   checks. Downloads use the existing dependency cache from
   [ADR-0011](0011-third-party-fetch.md). The tools are not installed for the
   user account and are not product runtime dependencies.
2. Build and test steps that invoke Cargo or Go run those cache binaries and
   depend on installation. Configuration does not use the network or probe
   `PATH`. `zig build tools:doctor` checks the installed versions.
3. `example:*` wrappers do not install a toolchain. Target execution is a separate
   qualification step.
4. Public step names are `fmt`, `lint`, `check`, `test`, `verify`,
   or `namespace:leaf` with at most one extra colon. The catalog is
   `build/commands.zig`. [Tooling](../development/tooling-and-rules.md) lists
   the commands.

## Consequences

- The first build or test that needs Rust or Go downloads the pinned archives.
  Later runs reuse the cache and work offline.
- Supported hosts are `aarch64-apple-darwin`, `x86_64-unknown-linux-gnu`, and
  `x86_64-pc-windows-msvc`. Another host fails `tools:install` with that list.
- The Windows GNU publisher still needs `gcc` and `dlltool` on `PATH`.
  `tools:doctor` reports their absence and does not install them.
- Node.js, `npm`, and the user-docs site stay outside `zig build` and `verify`.
