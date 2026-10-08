---
title: 术语表
description: Niobium 的产品构建、能力和部署术语。
---

规范术语由 [GLOSSARY.md](https://github.com/niobium-project/niobium/blob/main/GLOSSARY.md) 维护。历史 v1 页面保留其 manifest 和 engine 接口的局部定义。

| 术语 | 含义 |
|---|---|
| Author program（作者程序） | 在构建时生成类型化产品模型的源码 |
| Compiler（编译器） | 校验模型、固定依赖并组装 setup 的工具链 |
| Compiled program（编译后程序） | Runtime 消费的不可变产品表示 |
| Runtime（运行时） | 独立构建的产品程序与能力库执行宿主 |
| Setup（安装程序） | 包含 runtime、产品程序和固定依赖的产品安装程序 |
| Capability contract（能力契约） | 领域能力的接口与生命周期义务 |
| Capability library（能力库） | 固定的能力契约实现 |
| Capability instance（能力实例） | 具有独立输入、资源和状态的一次库绑定 |
| Host primitive（宿主原语） | 具有明确权限与副作用的版本化宿主机制 |
| Standard library（标准库） | 与产品库使用相同契约的官方库 |
| Preset（预设） | 构建时对库和产品约定的组合 |
| Component / workload（组件/工作负载） | 产品定义的部署单元/面向任务的组件选择 |
| Resource（资源） | 通过能力管理的具有稳定身份和所有权的实体 |
| Frozen plan（冻结计划） | 用于执行与恢复的持久化操作和内容 |
| Migration（迁移） | 产品或能力库状态版本之间的显式转换 |
| Bridge release（桥接发布） | 产品声明的升级路径中间步骤 |

[路线图](/zh/roadmap/)区分可执行基线和后续实施工作。
