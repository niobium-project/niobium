---
title: 学习 Niobium DSL
description: 编写 Starlark 产品，构建安装器，完成安装生命周期，并学习编写与编译模型。
---

构建一个安装 `README.txt` 的安装器，改变配置，再更新到第二个发布版本。随后扩展同一个示例，学习语言和编译模型。

教程使用可运行的 [DSL 示例](https://github.com/niobium-project/niobium/tree/main/examples/dsl-tutorial)。你需要有基本编程经验，并熟悉 shell 命令；无需提前了解 Starlark 或 Wasm。

## 学习路线

第一部分从产品作者源码出发，直到文件完成安装。请按顺序阅读，并保持使用同一个 shell：

1. [准备工具与项目](/zh/tutorial/setup/)：构建 SDK，创建示例的工作副本。
2. [构建第一个安装器](/zh/tutorial/first-installer/)：编写产品，编译安装器，检查安装后的文件。
3. [配置、更新与卸载](/zh/tutorial/configure-update-remove/)：改变安装输入，构建第二个发布版本，然后卸载。

第二部分解释这些声明如何生成编译后的产品：

4. [语法与构建时执行](/zh/tutorial/syntax/)：使用普通 Starlark 变量、集合、条件和循环。
5. [值、绑定与输入](/zh/tutorial/values-bindings/)：区分作者代码中的值与安装时解析的值。
6. [内容、权限与调用](/zh/tutorial/content-capabilities/)：用显式授权连接内容和能力库。
7. [函数与模块](/zh/tutorial/functions-modules/)：使用函数和 `load` 组织产品。
8. [编译与诊断](/zh/tutorial/compilation-diagnostics/)：检查构建输出，修复作者代码和输入错误。

## 源码、安装器与安装结果

作者程序是包含 Starlark 代码和 Niobium 声明的 `.star` 文件。Starlark 工作进程在构建时执行它，输出带类型的产品模型。编译器将模型与预编译原生运行时、固定能力库和内容一起打包。

```text
product.star + loaded modules + build arguments
                   |
          Starlark worker (build time)
                   |
        typed product + source map
                   |
     compiler + locked runtime, libraries, content
                   |
                  setup
                   |
      install / reconfigure / update / uninstall
                   |
           installation root/current/
```

交付的 `setup` 执行编译后产品的能力调用，不执行作者程序。能力库是计算期望安装资源的 Wasm Component；内容容器保存要部署的文件。

产品声明名为 `application` 的逻辑根目录，调用安装器时将它绑定到物理目录。授权限制库在该目录中可请求的内容和访问权限。运行时在发布文件前验证这些请求。

## 教程运行配置

这些章节使用当前实验性的 Component-v2 运行配置：命令行安装器、用户范围根目录，以及官方文件能力库。示例只使用一个根目录和一个内容容器。

命令使用 macOS arm64 上的 POSIX shell。Mach-O 组装使用 SDK 中锁定的临时签名工具。生产发布者身份、Gatekeeper 和公证需要单独的资格验证，见[运行时组装流程](https://github.com/niobium-project/niobium/blob/main/docs/development/cross-host-builds.md)。


从[准备工具与项目](/zh/tutorial/setup/)开始。
