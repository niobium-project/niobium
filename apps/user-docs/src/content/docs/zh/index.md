---
title: Niobium
description: 面向安装与分发的 DSL，包含 AOT 编译器和预编译原生 runtime。
---

Niobium 让产品团队通过语言 SDK 或 Starlark 编写安装程序模型。编译器验证能力契约，固定能力库与制品的身份，并将完整的预编译 runtime 封装为产品 setup。

Runtime 绑定用户选择与机器事实，执行固定的 Wasm 能力库，再应用持久化的宿主计划。官方库与产品库使用相同的受检接口。可选组件、SDK 共存和升级路径等产品策略由库与预设定义。

## 产品构建与执行

1. 通过作者 SDK 构建产品模型。函数、循环和跨项目组合使用源码语言。
2. 在构建时绑定库实现与制品。编译器验证契约并封装 runtime，无需重新链接。
3. 分发最终签名的 setup。Runtime 的宿主操作控制机器副作用、状态所有权与恢复。

作者源码仅在构建时执行。Wasm 能力库获得明确且有界的输入与宿主权限。恢复时重放冻结的宿主操作，不重新执行作者程序或能力库。

## 当前范围

首个可执行基线面向 macOS arm64、用户范围和 CLI，使用容量有界的单文件封装。新接口处于发布前阶段。依赖某项行为前，请查看[状态与平台](/zh/status/)中的证据。

[路线图](/zh/roadmap/)区分当前基线与后续可并行推进的 SDK、能力库、分发及平台工作。维护者规范和详细设计见仓库[文档索引](https://github.com/niobium-project/niobium/blob/main/docs/README.md)。

现有[教程](/zh/start/)及 manifest/`nbpack` 参考页保留用于旧实现，其 N1 结果不能证明新的编译器/runtime 边界已经验收。[新术语表](/zh/reference/glossary/)定义当前概念。

项目背景和维护方式见[关于本项目](/zh/about/)。
