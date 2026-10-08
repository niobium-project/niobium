---
title: 路线图
description: DSL/AOT 基线和后续可并行实施的能力。
---

当前方向是面向安装与分发的 DSL、AOT 编译器、预编译 runtime 和基于契约的能力库。🚧 表示当前交付，🔜 表示基线后可并行实施，🗓️ 表示后续验收。功能优先级与执行证据分开，证据见[状态与平台](/zh/status/)。

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

当前交付包括 Compiler 工程化、Wasm library SDK、Host primitives 与 stdlib 的详细设计，以及一个贯通三个作者入口、两个产品、独立能力库、迁移和恢复的 PoC。设计完成不等于其中的全部工程功能都已实现。

产品可通过能力库扩展行为；机器副作用仍需宿主提供相应的权限与事务操作。Runtime 不提供任意 shell 命令或环境权限。单文件 setup 属于当前封装方案，较大容量和各平台发布签名继续独立验收。

现有在线/离线安装、通道、Portable Run 和嵌入式更新的 N1 实现提供可复用的基础。它们需要接入新契约并取得 N2 证据后，才能算作新架构功能。

维护者的[工作包与依赖关系](https://github.com/niobium-project/niobium/blob/main/docs/roadmap-v0.2.md)包含逐项验收方案。平台义务见[平台支持](/zh/platforms/)；原生 Wayland 不在当前计划内。

[分发里程碑](https://github.com/niobium-project/niobium/blob/main/docs/adr/0020-distribution-delivery-milestones.md)
包含在线安装程序、安装前打开或解包的完整离线文件，以及无需单独解包即可开始安装的 SFX。
[分发工作清单](https://github.com/niobium-project/niobium/blob/main/docs/development/distribution-backlog.md)
保留签名、扫描、资源预算、离线有效期和维护程序生命周期工作。容量有界的 macOS PoC
不能证明这些完整发布形态已经通过验收。
