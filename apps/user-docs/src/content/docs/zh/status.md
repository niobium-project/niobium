---
title: 状态与平台
description: 当前 Component 方案的验收边界，以及各自保留范围内的历史结果。
---

## 当前标准 Component 方案

[验收计划](https://github.com/niobium-project/niobium/blob/main/docs/acceptance-plan.md)记录当前编译器、标准 WIT 库、内容/权限、原生封装和维护流程的实际命令、源码及制品身份与证据。基础 CLI 切片已在 [CI 37874568090](https://github.com/niobium-project/niobium/actions/runs/37874568090) 中通过原生发布、隔离组装和最终字节验收矩阵；当前接口仍为实验性接口。

Niobium 的 runtime 和 SDK 代码采用带版本的最低 CPU 配置。最终 Linux SDK 和 setup 字节也已在缺少 SHA/SSE4a 扩展的 x64 模拟环境中通过验证。该记录仅覆盖已记录的 CPU、文件系统和权限上下文，不能证明所有物理 CPU 或更旧操作系统均已验收。

作者入口一致性、标准 ABI/隔离 worker 和基础契约测试，与最终 setup 的生命周期、权限、签名及崩溃恢复验收是不同证据。编译成功不能代替运行最终字节；本地模拟目标的结果不能替代原生目标 CI。已记录的原生环境为 macOS 15.7.9 arm64、Ubuntu 24.04 x64 和 Windows Server 2025 x64。托管 runner 上的操作不能证明原生 Windows 普通用户令牌或通用 CPU 可移植性。整机范围、Developer ID、公证、Authenticode 和标准 v2 UI 仍为独立工作包；已记录的 Windows 私有 worker 副本清理限制也仍未关闭。

可通过 `zig build test:author test:component test:core` 运行基础检查，通过 `zig build core:e2e` 运行最终制品场景。完整门禁为 `zig build verify`。各平台的实际范围以验收记录为准，且仅覆盖记录中指定的源码版本。
