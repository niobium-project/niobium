# Niobium

[![codecov](https://codecov.io/gh/niobium-project/niobium/graph/badge.svg)](https://codecov.io/gh/niobium-project/niobium)

English | [Chinese](README.zh.md)

Niobium is an installation and distribution DSL with an AOT compiler, a precompiled native runtime and host-controlled Wasm capability libraries. Product authors compose installers through language SDKs or Starlark. The compiler fixes dependencies and packages the runtime; products define their distribution and upgrade policies through libraries and presets.

The architecture baseline is [ADR-0022](docs/adr/0022-installer-dsl-and-aot-toolchain.md). New interfaces are pre-release and may change. [N2 acceptance](docs/acceptance-plan-v0.2.md) records actual results; historical N1 evidence applies to the retained implementation.

## Build and verify

The native toolchain requires Zig 0.17.0. The Starlark build-time worker requires Go 1.25 or newer and a host C compiler for cgo. The initial native product lane targets macOS arm64, user scope and CLI.

```sh
zig build aot             # compiler, author ABI, guest examples and runtime template
zig build aot-test        # program/profile/host contract checks
zig build aot-e2e         # native products, migration, recovery and final image checks
zig build verify          # new architecture lane plus retained regression gates
```

Product assembly consumes a complete runtime template and preserves its executable code sections. The PoC fills a reserved 1 MiB product section and applies ad-hoc signing. Resource names use printable ASCII; installation roots may use Unicode. Publisher signing, larger carriers and additional platforms have separate qualification work.

[Compiler frontends](docs/spec/compiler-frontends-v1.md) defines authoring; [capability libraries](docs/spec/capability-library-v1.md) defines runtime extension. Existing `examples/hello` and manifest tutorials describe the legacy build API.

The [PoC workflow](docs/development/aot-poc.md) walks through authoring, assembly,
installation and an explicit state migration using two releases.

## Roadmap

🚧 current delivery · 🔜 parallel implementation after the baseline · 🗓️ later qualification. These marks describe work priority; execution results use the acceptance status vocabulary.

| Status | Feature |
|---|---|
| 🚧 | Programmable authoring and the AOT compiler |
| 🚧 | Precompiled runtime and fixed Wasm capability libraries |
| 🚧 | Transactional deployment and explicit state migration |
| 🔜 | Compiler caching, library SDK and additional host primitives |
| 🔜 | Python, TypeScript, Go and Rust author SDKs |
| 🔜 | Component, SDK and toolchain presets |
| 🔜 | Distribution, trust and channels as libraries |
| 🔜 | Online, offline-file and SFX delivery |
| 🗓️ | Large native images and publisher signing |
| 🗓️ | Standard UI, embedded maintenance and accessibility |
| 🗓️ | Windows/Linux and machine-scope qualification |

The [user roadmap](apps/user-docs/src/content/docs/roadmap.md) explains these items. The [maintainer roadmap](docs/roadmap-v0.2.md) assigns interfaces, owners, dependencies and acceptance.

## Background

Niobium is a hobby project that the author works on while employed at TongYuan. It is not part of TongYuan's commercial products. It supports creating installers for products, including internal, experimental and commercial work. TongYuan provides no direct support or steering. See [About the project](apps/user-docs/src/content/docs/about.md).

## Documentation

- User documentation: https://niobium-project.dev
- Architecture and contracts: [Documentation index](docs/README.md)
- Engineering designs: [Compiler](docs/design/compiler-engineering.md), [library SDK](docs/design/wasm-library-sdk.md), [host and stdlib](docs/design/host-primitives-and-stdlib.md)
- Development constraints: [AGENTS.md](AGENTS.md)
- Domain terms: [GLOSSARY.md](GLOSSARY.md)
- Evidence: [N2 acceptance](docs/acceptance-plan-v0.2.md), [historical N1](docs/acceptance-plan-v0.1.md)

## License

[MIT](LICENSE)
