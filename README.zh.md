# Niobium

[![codecov](https://codecov.io/gh/niobium-project/niobium/graph/badge.svg)](https://codecov.io/gh/niobium-project/niobium)

[English](README.md) | 简体中文

Niobium 是面向安装与分发的 DSL，包含 AOT 编译器、预编译原生 runtime 和由宿主管理权限的 Wasm 能力库。产品作者通过语言 SDK 或 Starlark 组合安装程序。编译器固定依赖并封装 runtime，产品通过库与预设定义分发和升级策略。

架构基线见 [ADR-0022](docs/adr/0022-installer-dsl-and-aot-toolchain.md)。新接口处于发布前阶段，仍可能变更。[N2 验收](docs/acceptance-plan-v0.2.md)记录实际结果；历史 N1 证据仅适用于保留的旧实现。

## 构建与验证

原生工具链需要 Zig 0.17.0。Starlark 构建端 worker 还需要 Go 1.25 或更高版本，以及用于 cgo 的主机 C 编译器。首个原生产品验收目标为 macOS arm64、用户范围和 CLI。

```sh
zig build aot             # 编译器、作者 ABI、能力库示例和 runtime 模板
zig build aot-test        # 产品模型、Wasm profile 与宿主契约检查
zig build aot-e2e         # 原生产品、迁移、恢复与最终封装检查
zig build verify          # 新架构验收与保留的回归门禁
```

产品组装使用完整的 runtime 模板，并保留其可执行代码段。PoC 填充预留的 1 MiB 产品段，再进行 ad-hoc 签名。资源名称使用可打印 ASCII，安装根目录允许 Unicode。发布者签名、更大容量的封装和其他平台分别验收。

[编译器前端规范](docs/spec/compiler-frontends-v1.md)定义产品构建接口；[能力库规范](docs/spec/capability-library-v1.md)定义运行时扩展。现有 `examples/hello` 和 manifest 教程描述旧构建 API。

[PoC 操作说明](docs/development/aot-poc.md)通过两个发布演示产品编写、组装、安装与显式状态迁移。

## 路线图

🚧 当前交付 · 🔜 基线之后可并行实施 · 🗓️ 后续验收。这些标记表示工作优先级，执行结果使用验收状态词汇。

| 状态 | 功能 |
|---|---|
| 🚧 | 程序化产品构建与 AOT 编译器 |
| 🚧 | 预编译 runtime 与固定的 Wasm 能力库 |
| 🚧 | 事务化部署与显式状态迁移 |
| 🔜 | 编译缓存、能力库 SDK 与更多宿主操作 |
| 🔜 | Python、TypeScript、Go 与 Rust 产品 SDK |
| 🔜 | 组件、SDK 与工具链预设 |
| 🔜 | 分发、信任与通道能力库 |
| 🔜 | 在线、完整离线文件与自解压安装程序 |
| 🗓️ | 大容量原生封装与发布者签名 |
| 🗓️ | 标准 UI、嵌入式维护与无障碍支持 |
| 🗓️ | Windows/Linux 与整机范围验收 |

[用户路线图](apps/user-docs/src/content/docs/zh/roadmap.md)解释这些功能。[维护者路线图](docs/roadmap-v0.2.md)定义接口、负责人、依赖关系与验收。

## 背景

Niobium 是作者在同元软控工作期间开发的业余项目，不属于同元软控的商业产品。它用于为包括内部、实验性及商业项目在内的产品制作安装程序。同元软控不提供直接支持或方向指导。参见[关于本项目](apps/user-docs/src/content/docs/zh/about.md)。

## 文档

- 用户文档：https://niobium-project.dev/zh/
- 架构与契约：[文档索引](docs/README.md)
- 工程设计：[编译器](docs/design/compiler-engineering.md)、[能力库 SDK](docs/design/wasm-library-sdk.md)、[宿主与标准库](docs/design/host-primitives-and-stdlib.md)
- 开发约束：[AGENTS.md](AGENTS.md)
- 领域术语：[GLOSSARY.md](GLOSSARY.md)
- 验收证据：[N2 验收](docs/acceptance-plan-v0.2.md)、[历史 N1](docs/acceptance-plan-v0.1.md)

## 许可证

[MIT](LICENSE)
