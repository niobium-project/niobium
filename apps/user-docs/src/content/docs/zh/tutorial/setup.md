---
title: 1. 准备工具与项目
description: 构建当前 SDK，为 Starlark 教程准备独立工作目录。
---

构建作者工具和编译器，再准备示例的锁定输入。本章完成后，你将拥有源码工作副本和发布版本 1 的构建目录。

## 前置条件

使用 macOS arm64、POSIX shell、Git 和 Zig 0.17.0。首次构建 SDK 需要网络。Zig 会安装发布 SDK 所用的固定 Rust 和 Go。编译已经准备好的产品时不需要它们。

[SDK 构建流程](https://github.com/niobium-project/niobium/blob/main/docs/development/cross-host-builds.md)规定原生目标要求。

## 构建 SDK

克隆仓库，或使用已有检出目录：

```sh
git clone https://github.com/niobium-project/niobium
cd niobium
```

第一部分的后续命令均从此检出目录的根目录执行。保持 shell 打开，以保留目录变量：

```sh
NIOBIUM_REPO="$PWD"
zig build core:sdk example:tutorial:tools --cache-poison=disallowed
```

SDK 将 Starlark 工作进程、编译器、原生运行时模板、Component 工作进程和官方文件库安装到 `zig-out/`。教程构建另外提供 `zig-out/bin/niobium-tutorial-prepare`。

## 准备工作副本

创建独立目录，将教程项目复制到其中：

```sh
TUTORIAL_WORK="$(mktemp -d /tmp/niobium-tutorial.XXXXXX)"
cp -R examples/dsl-tutorial "$TUTORIAL_WORK/source"
```

项目包含 `product.star`、模块化的替代写法，以及 `payload/README.txt`。教程中修改此副本，让仓库示例保持可供对照。

准备发布版本 1：

```sh
zig-out/bin/niobium-tutorial-prepare \
  --sdk "$NIOBIUM_REPO/zig-out" \
  --source "$TUTORIAL_WORK/source" \
  --out "$TUTORIAL_WORK/release1"
```

准备工具从 `payload/README.txt` 创建内容容器，捕获 SDK 输入，将精确长度和 SHA-256 身份写入锁文件。它还生成 `inputs.star`，向作者程序提供这些身份。

检查目录：

```sh
ls "$TUTORIAL_WORK/release1"
cat "$TUTORIAL_WORK/source/payload/README.txt"
```

目录包含复制的作者源码、`inputs.star`、`inputs.lock.json`、运行时及其元数据、Component 工作进程、文件 Component 和内容容器。它还包含第六章练习所需的小型 `fallback` 内容容器。在 macOS 上，它包含锁定的签名工具。

将此目录作为一个发布版本的输入集。内容改变后，将发布版本 2 准备到另一个目录；第一个目录仍保存发布版本 1 的输入集。

## 练习：找到源码与输出

找出改变已安装消息时需要编辑的文件，以及改变产品声明时需要编辑的文件。

消息来自 `$TUTORIAL_WORK/source/payload/README.txt`。声明来自 `$TUTORIAL_WORK/source/product.star`。`inputs.star` 和 `inputs.lock.json` 是生成的构建输入，其记录的身份必须与捕获的字节保持一致。

下一章：[构建第一个安装器](/zh/tutorial/first-installer/)。
