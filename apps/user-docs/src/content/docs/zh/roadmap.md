---
title: 路线图
description: 标准内容容器与 WIT 基础，以及可并行推进的产品能力。
---

Niobium 是面向安装与分发的 DSL，包含 AOT 编译器、预编译 runtime 和标准 WIT 能力契约。🚧 表示当前交付，🔜 表示基线后的并行工作，🗓️ 表示后续验收。优先级与[状态与平台](/zh/status/)中的执行证据分开。

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
| 🗓️ | 原生平台 CI 与整机范围验收 |

当前工作建立共享的类型化作者接口、编译绑定/缓存/诊断、标准 Component 执行、内容与权限契约，以及可恢复的原生维护机制。官方文件库和独立的内容生成库使用相同契约。设计基线和本地切片通过，不代表全部产品功能或平台已经完成。

可选模块、workload、SDK 共存和缺少前置依赖时的处理，属于产品库与预设。检测已有资源不代表取得其所有权。原生机制必须有界并经过授权；添加 Wasm 库不会自动增加 OS primitive 或任意进程权限。

[工作包](https://github.com/niobium-project/niobium/blob/main/docs/roadmap-v0.3.md)、[功能归属目录](https://github.com/niobium-project/niobium/blob/main/docs/feature-coverage.md)与[产品旅程](https://github.com/niobium-project/niobium/blob/main/docs/design/product-journeys.md)给出接口、依赖、反向测试向量和验收责任。

保留实现中的在线/离线分发、通道、Portable Run 和嵌入式更新，需要接入当前契约并补充新证据。[分发里程碑](https://github.com/niobium-project/niobium/blob/main/docs/adr/0020-distribution-delivery-milestones.md)与[分发工作清单](https://github.com/niobium-project/niobium/blob/main/docs/development/distribution-backlog.md)继续保留原有范围。单文件 Component setup 本身不能证明全部在线/离线/SFX 策略、发布者签名或原生应用元数据已经验收。

[平台支持](/zh/platforms/)保留项目的分层义务。本地模拟执行不能代替原生目标 CI；整机范围与标准 v2 UI 仍需独立验收。
