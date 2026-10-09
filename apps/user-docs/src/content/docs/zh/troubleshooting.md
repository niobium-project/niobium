---
title: 故障排查与常见问题
description: 排查当前 DSL 的编译与维护错误，并查阅保留的 v1 故障排查细节。
tableOfContents:
  maxHeadingLevel: 2
---

## 编译器诊断 { #compiler-diagnostics }

当前 DSL 的排错请从[编译与诊断](/zh/tutorial/compilation-diagnostics/)开始。Starlark 前端生成源码映射；当错误具备映射诊断时，编译器向标准错误输出的诊断 JSON 将绑定和类型错误定位到作者源码。锁定输入的捕获失败可能报告 `LockMismatch`，同时 `diagnostic: null`。先检查实际错误和命令阶段，再寻找源码位置。

教程演示了这两类失败，并验证编译失败会保留已有的 setup。编译器诊断描述构建时错误；下面保留的 `nbpack` 退出码表适用于另一套接口。

## Runtime 维护 { #runtime-maintenance }

安装及后续维护使用相同、完整的 `--root` 映射。Runtime 的 `--set` 绑定已声明的安装输入；Starlark 的 `--arg` 改变构建时的作者参数。两者的区别见[值与绑定](/zh/tutorial/values-bindings/)。

`KernelBusy` 表示协作的维护操作持有根目录锁。等待它结束后再重试。每次调用，包括 `status`，都可能从冻结计划完成兼容的待处理事务。报告故障时请保留所有权、计划和回执文件；删除这些文件可能使安全恢复无法继续。

[生命周期契约](https://github.com/niobium-project/niobium/blob/main/docs/spec/runtime-lifecycle.md)定义恢复和兼容性检查。教程中的[配置与更新步骤](/zh/tutorial/configure-update-remove/)使用当前 CLI。
