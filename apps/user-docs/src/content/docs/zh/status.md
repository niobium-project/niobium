---
title: 状态与平台
description: 当前 Component 方案的验收边界，以及各自保留范围内的历史结果。
---

## 当前标准 Component 方案

[验收计划 v0.3](https://github.com/niobium-project/niobium/blob/main/docs/acceptance-plan-v0.3.md)记录当前编译器、标准 WIT 库、内容/权限、原生封装和维护流程的实际命令、源码及制品身份与证据。基础 CLI 切片已在 [CI 37874568090](https://github.com/niobium-project/niobium/actions/runs/37874568090) 中通过原生发布、隔离组装和最终字节验收矩阵；当前接口仍为实验性接口。

Niobium 的 runtime 和 SDK 代码采用带版本的最低 CPU 配置。最终 Linux SDK 和 setup 字节也已在缺少 SHA/SSE4a 扩展的 x64 模拟环境中通过验证。该记录仅覆盖已记录的 CPU、文件系统和权限上下文，不能证明所有物理 CPU 或更旧操作系统均已验收。

作者入口一致性、标准 ABI/隔离 worker 和基础契约测试，与最终 setup 的生命周期、权限、签名及崩溃恢复验收是不同证据。编译成功不能代替运行最终字节；本地模拟目标的结果不能替代原生目标 CI。已记录的原生环境为 macOS 15.7.9 arm64、Ubuntu 24.04 x64 和 Windows Server 2025 x64。托管 runner 上的操作不能证明原生 Windows 普通用户令牌或通用 CPU 可移植性。整机范围、Developer ID、公证、Authenticode 和标准 v2 UI 仍为独立工作包；已记录的 Windows 私有 worker 副本清理限制也仍未关闭。

可通过 `zig build author-v2-test component-test core-test` 运行基础检查，通过 `zig build core-e2e` 运行最终制品场景。完整门禁为 `zig build verify`。各平台的实际范围以验收记录为准，而非本文中的旧表格。

[验收 v0.2](https://github.com/niobium-project/niobium/blob/main/docs/acceptance-plan-v0.2.md)保留原 Core Wasm/WAMR PoC 范围。下面的 N1 表格继续保留旧 manifest/engine 的历史结果，不能证明当前方案已经验收。

## 历史 v1 状态


Niobium 0.1 是一个用来证明模型可行的纵向切片，尚不能用于生产环境。本页是本站关于验证情况的唯一说明，其他页面都链接到这里，而不重复其内容。

状态只使用五个值：

| 状态 | 含义 |
|---|---|
| `PASS` | 已由自动化测试或构建门禁验证，并有记录的证据 |
| `FAIL` | 已验证，且失败 |
| `BLOCKED` | 暂时无法运行；原因已记录 |
| `NOT_RUN` | 可以运行，但尚未运行 |
| `DEFERRED` | 有意不在本版本范围内 |

这些历史 N1 记录的事实来源是仓库中的[验收计划](https://github.com/niobium-project/niobium/blob/main/docs/acceptance-plan-v0.1.md)和[开发路线图](https://github.com/niobium-project/niobium/blob/main/docs/roadmap-v0.1.md)；如果本页与它们不一致，以它们为准。当前计划中的工作见[路线图](/zh/roadmap/)。

## 历史记录的验证环境

以下历史 `PASS` 条目都来自在 macOS arm64 主机上运行的 `zig build verify`；端到端测试套件也在 Debian bookworm arm64 容器中通过。该历史记录形成时，尚未在真实 Windows 机器或完整 Linux 桌面上验证。

构建目标是 `x86_64-windows`、`aarch64-macos` 和 `x86_64-linux`，另有用于虚拟机测试的 `aarch64-linux`；它们的支持层级和参考操作系统见[平台支持](/zh/platforms/)。所有目标都能交叉编译并通过二进制检查，三个发布目标的 `setup` 都小于 30 MiB（N1-AC-15 到 N1-AC-17：`PASS`）。能为某个平台编译，并不等于已在该平台上验证。

## 历史用户旅程

| ID | 旅程 | 状态 |
|---|---|---|
| N1-UJ-01 | 从 HTTP 仓库进行用户范围在线安装；调用 App Bootstrap | `PASS` |
| N1-UJ-02 | 管理员静默安装，`install --silent --json --scope machine` | `BLOCKED` |
| N1-UJ-03 | 更新到更高的 `release_sequence` | `PASS` |
| N1-UJ-04 | 事故回滚：更高的序号发布较旧的应用版本 | `PASS` |
| N1-UJ-05 | 修复恢复被删除或被篡改的文件 | `PASS` |
| N1-UJ-06 | 卸载后安装根目录和系统集成都被清理干净 | `PASS` |
| N1-UJ-07 | 从离线包安装 | `PASS` |
| N1-UJ-08 | 便携运行：授权、缓存、执行、清理 | `PASS` |
| N1-UJ-09 | 一个 C 程序通过 C ABI 完成检查、解析、获取、暂存和提交 | `PASS` |
| N1-UJ-10 | 在 macOS 上通过安装程序窗口的五个界面完成安装（人工走查） | `NOT_RUN` |

N1-UJ-02 被阻塞的原因与下面的真实系统冒烟测试相同，另外还因为冒烟工具目前只运行用户范围。

## 历史保证

| ID | 保证 | 状态 |
|---|---|---|
| N1-INV-01 | 从任意中止点恢复后，生效的版本是旧版本或新版本 | `PASS` |
| N1-INV-02 | 解包制品不能写到暂存目录之外 | `PASS` |
| N1-INV-03 | 被禁止的清单和组件字段会被拒绝 | `PASS` |
| N1-INV-04 | 提权助手只接受其封闭的操作集合，且只在受管根目录内 | `PASS` |
| N1-INV-05 | TUF 拒绝过期、回滚、伪造、未达阈值和不匹配的元数据 | `PASS` |
| N1-INV-06 | `release_sequence` 严格递增；应用版本可以下降 | `PASS` |
| N1-INV-07 | 窗口和命令行运行同一个引擎和同一个计划 | `PASS` |
| N1-INV-08 | 未知的 schema 版本和过旧的安装程序以关闭方式失败 | `PASS` |

这些测试在构建主机上运行，对象是注入了故障的测试平台以及主机的真实文件系统。它们不能作为尚未运行的平台（见下文）的证据。

## 历史平台记录

| 项目 | 状态 |
|---|---|
| 真实系统冒烟测试，Windows 11（N1-AC-18） | `BLOCKED` |
| 真实系统冒烟测试，Ubuntu 24.04 arm64（N1-AC-19） | `BLOCKED` |
| Authenticode 和 Apple Developer ID 签名与公证 | `DEFERRED` |
| 原生 Wayland 窗口后端（Linux 使用 X11） | `DEFERRED` |
| 屏幕阅读器桥接（UI Automation、NSAccessibility、AT-SPI） | `DEFERRED` |
| Linux 上的原生文件夹选择器 | `DEFERRED` |

真实系统冒烟测试被阻塞，是因为上次运行测试套件时测试虚拟机没有在运行。每个平台承诺了什么、还缺哪些测试通道，见[平台支持](/zh/platforms/)。

## 推迟的功能

| 项目 | 状态 |
|---|---|
| 面向 Electron 宿主的嵌入式更新（`distribution.node`） | `DEFERRED` |
| 把协议处理程序、开机自启项和环境变量作为能力 | `DEFERRED` |

## 历史记录中没有验收条目的缺口

- `nbpack` 目前还不能轮换 root 或在线密钥；客户端已经能验证轮换后的 root（[签名与密钥管理](/zh/guides/sign-and-keys/#rotate-or-recover-keys)）。
- 没有已发布的安全策略或私密报告渠道（[安全](/zh/security/#report-a-vulnerability)）。
- 构建 API 在 0.1 中不做兼容性承诺：请固定一个提交。`setup` 的退出码和 JSON 事件 schema 被声明为兼容性契约（[退出码](/zh/reference/exit-codes/)），C ABI 只通过在其带版本的函数表末尾追加来变更。
