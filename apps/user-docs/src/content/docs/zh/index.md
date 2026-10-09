---
title: Niobium
description: 面向安装与分发的 DSL，包含 AOT 编译器和预编译原生 runtime。
---

Niobium 让产品团队通过语言 SDK 或 Starlark 编写安装程序模型。编译器验证能力契约，固定能力库与制品的身份，并将完整的预编译 runtime 封装为产品 setup。

Runtime 绑定用户选择与机器事实，执行固定的 Wasm 能力库，再应用持久化的宿主计划。官方库与产品库使用相同的受检接口。可选组件、SDK 共存和升级路径等产品策略由库与预设定义。

## 产品构建与执行

1. 通过作者 SDK 构建产品模型。函数、循环和跨项目组合使用源码语言。
2. 在构建时绑定库实现与制品。编译器验证契约并封装 runtime，无需重新链接。
3. 完成平台方案要求的签名后，分发最终 setup。Runtime 的宿主操作控制机器副作用、状态所有权与恢复。

作者源码仅在构建时执行。Wasm 能力库接收有界的类型化输入，由宿主验证其提出的操作。恢复时重放冻结的宿主操作，不重新执行作者程序或能力库。

## 当前范围

当前实验性方案采用标准 WIT/Component 契约、Wasmtime/Pulley、规范化 POSIX pax 内容，以及明确的可移植权限策略。原生 Zig、C 和 Starlark 构造相同模型。编译器解析完整输入类型和源码诊断，固定依赖，并组装预编译 runtime，不针对具体产品重新链接。

CLI/用户范围基础已有原生托管 CI 和本地验收切片的记录。PE/ELF/Mach-O 组装与目标平台执行分别记录。原生 CI 验收限于记录中的 runner 上下文；整机范围和发布者身份认证仍是独立工作。证据边界见[状态与平台](/zh/status/)。

从 [DSL 入门教程](/zh/tutorial/)开始，构建、安装和更新一个小型 Starlark 产品，再学习如何编写与编译它的模型。

SDK 细节见[作者接口指南](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring-v2.md)、[Component SDK](https://github.com/niobium-project/niobium/blob/main/docs/development/component-library-sdk.md)和[跨主机构建指南](https://github.com/niobium-project/niobium/blob/main/docs/development/cross-host-builds.md)。[路线图](/zh/roadmap/)及维护者[文档索引](https://github.com/niobium-project/niobium/blob/main/docs/README.md)区分基础机制、产品预设、完整语言 SDK 和后续平台验收。

侧边栏将旧版 v1 文档单独分组。保留的 [v1 教程](/zh/start/)及 manifest/`nbpack` 参考页描述它们原有的接口和证据。[术语表](/zh/reference/glossary/)定义当前领域概念。

项目背景和维护方式见[关于本项目](/zh/about/)。
