---
title: 安全
description: Component 授权、完整性与发布者信任、保留的 v1 防御措施，以及漏洞报告。
tableOfContents:
  maxHeadingLevel: 2
---

## 当前 Component 方案 { #current-component-profile }

当前安装程序封装类型化产品模型、固定的能力 Component，以及身份经过检查的内容。作者源码在构建时执行。能力库接收有界的类型化输入与明确授予的权限；它们没有默认的文件系统、网络、进程或提权权限。

宿主先验证期望资源和原生访问权限，再冻结持久化计划。恢复使用该计划，不重新执行作者代码或 Component。这些边界见[授权与访问权限](/zh/concepts/privilege/)和[事务与恢复](/zh/concepts/transactions/)。

## 完整性与发布者信任 { #integrity-and-publisher-trust }

锁定摘要标识输入字节。Setup 镜像中的哈希检查内部一致性；自行声明的哈希不能认证发布者身份。构建过程信任作者源码、选定的依赖、工具链与 runtime 发布者。

[锁定输入契约](https://github.com/niobium-project/niobium/blob/main/docs/spec/compiler-inputs.md)和 [setup 镜像契约](https://github.com/niobium-project/niobium/blob/main/docs/spec/setup-image.md)定义这些检查。当前执行证据，以及尚待完成的签名、公证和整机范围工作，见[状态与平台](/zh/status/)。下面保留的 TUF 工作流有独立的契约和证据。
