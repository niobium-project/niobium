---
title: 平台支持
description: Niobium 面向哪些平台、每个支持层级承诺什么，以及后续计划。
---

此页记录平台层级义务和仍需完成的资格验收。当前 Component 证据与保留的 v1 记录在[状态与平台](/zh/status/)上各自保留其范围。

Niobium 把它构建的平台分为三个层级。层级说明项目在该平台上承诺什么；这些承诺目前是否兑现，记录在[状态与平台](/zh/status/)上，那是唯一报告结果的页面。

这份列表刻意保持简短。Niobium 由一个人在业余时间维护，背后没有公司资源（[关于本项目](/zh/about/)），而每个一级平台都会让每次变更多出构建、测试和发布的时间。

## 层级

| 层级 | 每次变更都构建 | 发布前在真实系统上测试 | 可以阻塞发布 | 修复 |
|---|---|---|---|---|
| 一级（Tier 1） | 是 | 必须 | 是 | 最优先 |
| 二级（Tier 2） | 是 | 尽力而为 | 否 | 时间允许时 |
| 三级（Tier 3） | 否 | 否 | 否 | 仅当有志愿负责人时 |

- **每次变更都构建**指以 ReleaseSafe 模式交叉编译该目标，且其二进制文件通过二进制检查（允许的动态库、PE 标志、不存在可写且可执行的内存）。Component runtime 发布检查其原生 ABI 配置、30 MiB 的 runtime 大小上限和增长限制；产品载荷容量另行约束（[ADR-0024](https://github.com/niobium-project/niobium/blob/main/docs/adr/0024-native-runtime-dependency-qualification.md)）。
- **在真实系统上测试**指在参考操作系统上运行平台契约测试套件、端到端的安装、更新、修复和卸载场景以及一次冒烟测试。对一级平台而言，已知的失败会阻塞发布；无法运行的测试在发布说明中报告为 `BLOCKED` 或 `NOT_RUN`，绝不报告为通过。
- **三级**平台是候选平台。默认不为它们构建任何东西，也不对它们做任何承诺。

## 当前平台

| 目标 | 层级 | 参考操作系统 | 说明 |
|---|---|---|---|
| `aarch64-macos` | 1 | Apple 芯片上的 macOS | 最低 macOS 版本尚未确定 |
| `x86_64-windows` | 1 | Windows 11（x64） | |
| `x86_64-linux` | 1 | Ubuntu 24.04 LTS | 已测量的 Component GNU runtime 需要 glibc 2.36 和声明的加载器；其他发行版尚未验收 |
| `aarch64-linux` | 2 | Ubuntu 24.04（ARM64） | 会构建并检查，用于虚拟机冒烟测试；尚不是发布目标，因此不适用大小预算 |

每个目标的结果见[状态与平台](/zh/status/)。原生依赖按 OS 和 ABI 在 [ADR-0024](https://github.com/niobium-project/niobium/blob/main/docs/adr/0024-native-runtime-dependency-qualification.md) 下分别验收；GNU 和静态 musl 是不同配置。发布的 runtime 和 SDK 的 CPU 基线遵循 [ADR-0025](https://github.com/niobium-project/niobium/blob/main/docs/adr/0025-baseline-cpu-runtime-publication.md)。设置基线或交叉构建成功，不能证明所有 CPU 或更旧操作系统均已验收。

## 路线图 { #roadmap }

本节只涉及平台。计划中的功能见[路线图](/zh/roadmap/)。

### 第一个一级平台发布之前

每个一级平台的承诺与其测试通道之间仍有差距：

- **`x86_64-linux`：** 当前 Component 方案已有原生托管 Ubuntu 24.04 x64 CI 记录。更旧发行版和通用物理 CPU 可移植性不在该证据范围内。
- **`x86_64-windows`：** 原生托管 CI 在 Windows Server 2025 x64 上运行。该 runner 上下文不能证明 Windows 11 x64 参考系统或原生普通用户令牌已验收。Windows 11 ARM64/x64 模拟环境中的普通用户记录继续保留其独立范围。
- **所有平台：** 当前验收覆盖用户范围；整机范围和标准 v2 UI 仍是独立工作包。
- **`aarch64-macos`：** 已有原生托管 macOS 15.7.9 arm64 CI 记录。最低支持的 macOS 版本仍未确定；保留的 v1 图形界面人工走查仍是历史 `NOT_RUN` 记录。

### 候选平台 { #candidates }

| 候选 | 层级 | 需要什么 |
|---|---|---|
| `aarch64-windows` | 3 | 一个构建目标和二进制检查条目，以及一条在 ARM64 版 Windows 11 上的真实系统通道 |
| 麒麟（Kylin）和统信（UOS），x86_64 和 aarch64 | 3 | 每个发行版一条真实系统通道，检查原生 ABI、加载器、CPU 前置要求和桌面集成（`.desktop` 条目、MIME 包、systemd 单元、XDG 目录）；静态 musl 证据不能证明 GNU runtime 已验收 |

### 不在计划内 { #not-planned }

- **保留的 v1 窗口的原生 Wayland 后端。** 在 Wayland 会话中，该窗口通过 XWayland 运行（[ADR-0010](https://github.com/niobium-project/niobium/blob/main/docs/adr/0010-x11-now-wayland-deferred.md)）。当前 Component runtime 无界面；标准 v2 UI 有独立的实现与验收工作。

## 在层级之间调整

一个平台在满足以下全部条件时升到更高层级：

- 在参考操作系统上有一条可重复、能产生记录证据的测试通道；
- 有一个明确的参考操作系统版本；
- 有一位有时间维持该通道运行的维护者。

升入一级还需要一项记录在案的决策，因为它会给每次发布增加工作。如果一个一级平台的真实系统通道连续两次发布都不可用，它会降到二级。

欢迎移植到三级候选平台，前提是有人持续维持其测试通道，且不给一级平台增加工作。这项策略本身记录在 [ADR-0014](https://github.com/niobium-project/niobium/blob/main/docs/adr/0014-tier-based-platform-support.md) 中。
