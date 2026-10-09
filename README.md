# Niobium

[![codecov](https://codecov.io/gh/niobium-project/niobium/graph/badge.svg)](https://codecov.io/gh/niobium-project/niobium)

English | [Chinese](README.zh.md)

Niobium is an installation and distribution DSL with an AOT compiler, a
precompiled native runtime and host-controlled Wasm capability libraries. Product
authors use native Zig/C APIs or Starlark; language SDKs share the compiler
backend. Libraries and presets own product selection, distribution and upgrade
policy.

[ADR-0023](docs/adr/0023-standard-content-and-component-contracts.md) establishes
the current standard-content/WIT baseline. These interfaces are experimental and
pre-release. [Acceptance v0.3](docs/acceptance-plan-v0.3.md) records current results;
the older acceptance plans retain their own implementation and platform scope.

## Build and verify

Source builds need Zig 0.17.0. `zig build` installs pinned Rust 1.96.1 and Go 1.26.8
into `.cache/tools` when a build or test step needs them. The build also fetches
pinned Wasm tools. Product assembly consumes precompiled runtime bytes and does
not need those compilers. See
[cross-host builds](docs/development/cross-host-builds.md#build-the-host-sdk-and-a-runtime-template).

```sh
zig build compiler:build runtime:build  # host compiler and complete runtime template
zig build test:author         # native Zig, C and Starlark author parity
zig build test:component         # standard WIT/Canonical ABI and isolated worker
zig build test:core              # content, access, types and compiler foundations
zig build core:e2e               # final setup, lifecycle, migration and recovery
zig build verify                # current gates and retained regressions
```

The current runtime is a headless user-scope profile. Standard WIT and community
bindgen drive Wasmtime/Pulley; guests receive typed inputs and prebound observations
without ambient WASI or machine authority. Canonical POSIX pax containers preserve
logical file/directory/link structure; deployment access is an explicit separate
policy. PE, ELF and Mach-O assembly preserves the template's executable code and
binds its native prefix, product and payload identities.

Local native and emulated target runs are recorded individually. Native hosted CI
qualifies user-scope operations in its recorded runner contexts. These records do
not establish machine scope, full native application metadata, publisher
authentication or notarization. Further qualification remains in progress.
The 1 MiB section, ASCII resource names and WAMR profile belong to the retained v1
PoC, not the current content/Component contracts.

Start with the [DSL tutorial](apps/user-docs/src/content/docs/tutorial/index.md)
and its [runnable example](examples/dsl-tutorial/) to build your first Starlark product.
For SDK details, use [authoring v2](docs/development/authoring-v2.md), the
[Component SDK](docs/development/component-library-sdk.md), and
[cross-host builds](docs/development/cross-host-builds.md).
The [current contracts](docs/README.md) define the shared compiler and runtime
boundaries. `examples/hello`, manifest tutorials and the older
[PoC workflow](docs/development/aot-poc.md) retain their original API scope.

## Roadmap

🚧 current delivery · 🔜 parallel implementation after the baseline · 🗓️ later
qualification. These are priorities, not blanket completion or support claims.

| Status | Feature |
|---|---|
| 🚧 | Programmable authoring and the AOT compiler |
| 🚧 | Precompiled runtime and fixed Wasm capability libraries |
| 🚧 | Standard content, access and cross-host native assembly |
| 🚧 | Transactional deployment and explicit state migration |
| 🔜 | Incremental compiler tooling, SDK packaging and additional host primitives |
| 🔜 | Python, TypeScript, Go and Rust author SDKs |
| 🔜 | Component, SDK and toolchain presets |
| 🔜 | Distribution, trust and channels as libraries |
| 🔜 | Online, offline-file and SFX product profiles |
| 🗓️ | Publisher signing and notarization qualification |
| 🗓️ | Standard UI, embedded maintenance and accessibility |
| 🗓️ | Additional native-platform and machine-scope qualification |

The [user roadmap](apps/user-docs/src/content/docs/roadmap.md) explains these items.
The [maintainer roadmap](docs/roadmap-v0.3.md),
[feature ownership catalog](docs/feature-coverage.md) and
[product journeys](docs/design/product-journeys.md) assign interfaces, owners,
dependencies and acceptance.

## Background

Niobium is a hobby project that the author works on while employed at TongYuan.
It is not part of TongYuan's commercial products. It supports creating installers
for internal, experimental and commercial products. TongYuan provides no direct
support or steering. See [About the project](apps/user-docs/src/content/docs/about.md).

## Documentation

- User documentation: https://niobium-project.dev
- Architecture and contracts: [Documentation index](docs/README.md)
- Engineering designs: [Compiler](docs/design/compiler-engineering.md), [library SDK](docs/design/wasm-library-sdk.md), [host and stdlib](docs/design/host-primitives-and-stdlib.md)
- Development constraints: [AGENTS.md](AGENTS.md)
- Domain terms: [GLOSSARY.md](GLOSSARY.md)
- Evidence: [Current v0.3](docs/acceptance-plan-v0.3.md), [retained v0.2](docs/acceptance-plan-v0.2.md), [historical N1](docs/acceptance-plan-v0.1.md)

## License

[MIT](LICENSE)
