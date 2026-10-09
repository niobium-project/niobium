# Niobium

[![codecov](https://codecov.io/gh/niobium-project/niobium/graph/badge.svg)](https://codecov.io/gh/niobium-project/niobium)

[English](README.md) | 简体中文

Niobium 是面向安装与分发的 DSL，包含 AOT 编译器、预编译原生 runtime 和由宿主管理权限的 Wasm 能力库。产品作者使用原生 Zig/C API 或 Starlark，各语言 SDK 共享编译后端。产品选择、分发和升级策略由能力库与预设定义。

[ADR-0023](docs/adr/0023-standard-content-and-component-contracts.md)确立了当前的标准内容容器与 WIT 架构基线。接口仍处于实验性、发布前阶段。[验收计划 v0.3](docs/acceptance-plan-v0.3.md)记录当前结果；旧验收计划继续保留各自的实现及平台范围。

## 构建与验证

源码构建需要 Zig 0.17.0。构建或测试步骤需要时，`zig build` 会把固定的 Rust 1.96.1 和 Go 1.26.8 安装到 `.cache/tools`。构建图还会获取固定版本的 Wasm 工具。产品组装消费预编译的 runtime 字节，不需要这些编译器。见[跨主机构建](docs/development/cross-host-builds.md#build-the-host-sdk-and-a-runtime-template)。

```sh
zig build compiler:build runtime:build  # 主机编译器与完整 runtime 模板
zig build test:author         # 原生 Zig、C 与 Starlark 作者入口一致性
zig build test:component         # 标准 WIT、Canonical ABI 与隔离 worker
zig build test:core              # 内容、权限、类型和编译器基础契约
zig build core:e2e               # 最终 setup、生命周期、迁移和恢复
zig build verify                # 当前门禁与保留的回归测试
```

当前 runtime 是无界面的用户范围方案。标准 WIT 与社区 bindgen 接入 Wasmtime/Pulley；能力库接收类型化输入和预先绑定的观察结果，不获得隐式 WASI 或机器操作权限。规范化 POSIX pax 容器保存文件、目录和链接的逻辑结构，部署权限通过独立策略明确表达。PE、ELF 与 Mach-O 组装保留模板的可执行代码，并绑定原生前缀、产品及载荷身份。

本地原生或模拟目标的执行分别记录。原生托管 CI 验收覆盖已记录 runner 上下文中的用户范围操作。这些记录不能证明整机范围、完整原生应用元数据、发布者身份认证或公证已经验收，进一步的资格确认仍在进行。1 MiB 预留段、ASCII 资源名称和 WAMR profile 属于保留的 v1 PoC，不是当前内容与 Component 契约的限制。

从 [DSL 入门教程](apps/user-docs/src/content/docs/zh/tutorial/index.md)及其[可运行示例](examples/dsl-tutorial/)开始，构建你的第一个 Starlark 产品。SDK 细节见[作者接口 v2](docs/development/authoring-v2.md)、[Component SDK](docs/development/component-library-sdk.md)和[跨主机构建](docs/development/cross-host-builds.md)。[当前契约](docs/README.md)定义共享编译器及 runtime 的边界。`examples/hello`、manifest 教程和旧 [PoC 操作说明](docs/development/aot-poc.md)保留原有 API 范围。

## 路线图

🚧 当前交付 · 🔜 基线之后可并行实施 · 🗓️ 后续验收。这些标记表示优先级，不代表全部功能完成或平台支持声明。

| 状态 | 功能 |
|---|---|
| 🚧 | 程序化产品构建与 AOT 编译器 |
| 🚧 | 预编译 runtime 与固定的 Wasm 能力库 |
| 🚧 | 标准内容容器、权限与跨主机原生封装 |
| 🚧 | 事务化部署与显式状态迁移 |
| 🔜 | 增量编译工具、SDK 发布与更多宿主操作 |
| 🔜 | Python、TypeScript、Go 与 Rust 产品 SDK |
| 🔜 | 组件、SDK 与工具链预设 |
| 🔜 | 分发、信任与通道能力库 |
| 🔜 | 在线、离线文件与自解压产品方案 |
| 🗓️ | 发布者签名与公证验收 |
| 🗓️ | 标准 UI、嵌入式维护与无障碍支持 |
| 🗓️ | 更多原生平台与整机范围验收 |

[用户路线图](apps/user-docs/src/content/docs/zh/roadmap.md)解释这些项目。[维护者路线图](docs/roadmap-v0.3.md)、[功能归属目录](docs/feature-coverage.md)与[产品旅程](docs/design/product-journeys.md)定义接口、负责人、依赖关系和验收。

## 背景

Niobium 是作者在同元软控工作期间开发的业余项目，不属于同元软控的商业产品。它用于为内部、实验性及商业产品制作安装程序。同元软控不提供直接支持或方向指导。参见[关于本项目](apps/user-docs/src/content/docs/zh/about.md)。

## 文档

- 用户文档：https://niobium-project.dev/zh/
- 架构与契约：[文档索引](docs/README.md)
- 工程设计：[编译器](docs/design/compiler-engineering.md)、[能力库 SDK](docs/design/wasm-library-sdk.md)、[宿主与标准库](docs/design/host-primitives-and-stdlib.md)
- 开发约束：[AGENTS.md](AGENTS.md)
- 领域术语：[GLOSSARY.md](GLOSSARY.md)
- 验收证据：[当前 v0.3](docs/acceptance-plan-v0.3.md)、[保留的 v0.2](docs/acceptance-plan-v0.2.md)、[历史 N1](docs/acceptance-plan-v0.1.md)

## 许可证

[MIT](LICENSE)
