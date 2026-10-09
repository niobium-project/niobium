---
title: 3. 配置、更新与卸载
description: 重配置安装输入，构建并应用第二个发布版本，再验证卸载行为。
---

关闭并恢复已安装的内容，再更新消息并卸载。从[构建第一个安装器](/zh/tutorial/first-installer/)继续，使用同一个 shell，并保持在检出目录的根目录。

## 改变安装输入

在已安装的发布版本上将 `enabled` 设为 false：

```sh
"$TUTORIAL_WORK/release1/setup" reconfigure \
  --root "application=$TUTORIAL_WORK/installation" --set enabled=false
test ! -e "$TUTORIAL_WORK/installation/current/hello/README.txt"
"$TUTORIAL_WORK/release1/setup" status \
  --root "application=$TUTORIAL_WORK/installation"
```

文件不存在时，`test` 命令成功退出且不输出内容。产品仍然处于已安装状态：文件库针对 `enabled=false` 返回空的期望内容集。

恢复内容：

```sh
"$TUTORIAL_WORK/release1/setup" reconfigure \
  --root "application=$TUTORIAL_WORK/installation" --set enabled=true
cat "$TUTORIAL_WORK/installation/current/hello/README.txt"
```

文件再次包含发布版本 1 的消息。重配置使用已安装的产品版本，不会重新执行作者程序或构建另一个安装器。

## 构建发布版本 2

修改源码副本中的内容：

```sh
printf '%s\n' 'Hello from the Niobium DSL tutorial, release 2.' \
  > "$TUTORIAL_WORK/source/payload/README.txt"
```

准备独立输入集，并以发布序号 2 执行作者程序：

```sh
zig-out/bin/niobium-tutorial-prepare \
  --sdk "$NIOBIUM_REPO/zig-out" \
  --source "$TUTORIAL_WORK/source" \
  --out "$TUTORIAL_WORK/release2"
zig-out/bin/nb-starlark-v2 \
  --source "$TUTORIAL_WORK/release2/product.star" \
  --out "$TUTORIAL_WORK/release2/product.program.json" \
  --source-map "$TUTORIAL_WORK/release2/product.sources.json" \
  --arg release_sequence=2
```

准备工具记录改变后的内容身份。`--arg release_sequence=2` 改变发布序号，同时保留产品 ID、模型版本和调用状态版本。递增的序号让此版本排在发布版本 1 之后。

组装第二个安装器：

```sh
zig-out/bin/nb-builder compile \
  --program "$TUTORIAL_WORK/release2/product.program.json" \
  --source-map "$TUTORIAL_WORK/release2/product.sources.json" \
  --lock "$TUTORIAL_WORK/release2/inputs.lock.json" \
  --runtime runtime --runtime-metadata runtime-metadata --worker worker \
  --input "runtime=$TUTORIAL_WORK/release2/runtime" \
  --input "runtime-metadata=$TUTORIAL_WORK/release2/runtime-metadata" \
  --input "worker=$TUTORIAL_WORK/release2/worker" \
  --input "files=$TUTORIAL_WORK/release2/files" \
  --input "content=$TUTORIAL_WORK/release2/content" \
  --input "fallback=$TUTORIAL_WORK/release2/fallback" \
  --signer signer --input "signer=$TUTORIAL_WORK/release2/signer" \
  --output "$TUTORIAL_WORK/release2/setup"
```

两个安装器都保留在各自的发布目录中。发布版本 2 内嵌新消息，不会从通道或仓库获取更新。

## 应用更新

将新安装器用于已有安装：

```sh
"$TUTORIAL_WORK/release2/setup" update \
  --root "application=$TUTORIAL_WORK/installation"
"$TUTORIAL_WORK/release2/setup" status \
  --root "application=$TUTORIAL_WORK/installation"
cat "$TUTORIAL_WORK/installation/current/hello/README.txt"
```

文件内容为：

```text
Hello from the Niobium DSL tutorial, release 2.
```

根目录映射保持不变。运行时发布包含新内容的代，并持久化新的发布版本。[迁移契约](https://github.com/niobium-project/niobium/blob/main/docs/spec/migration.md)分别规定模型版本和调用状态版本改变时的规则。

## 卸载并检查结果

使用发布版本 2 的安装器：

```sh
"$TUTORIAL_WORK/release2/setup" uninstall \
  --root "application=$TUTORIAL_WORK/installation"
test ! -e "$TUTORIAL_WORK/installation/current"
test ! -e "$TUTORIAL_WORK/installation/.niobium-v2/installation.json"
"$TUTORIAL_WORK/release2/setup" status \
  --root "application=$TUTORIAL_WORK/installation"
```

两个 `test` 命令成功退出且不输出内容。卸载移除已发布内容和活动安装快照。所有权记录和已验证内容存储可能保留在 `.niobium-v2/` 下；卸载不承诺删除整个根目录。

运行时只在受管资源的内容和原生身份仍与记录的清单一致时删除它们。检查此结果时，请保持教程文件不变。被修改或未知的文件可能保留在退役的代中。

## 练习：选择执行阶段

分别为隐藏已安装文件、改变文件文本、改变产品发布序号选择操作。

使用 `reconfigure --set enabled=false` 隐藏文件。改变文本时，编辑源码内容并准备新的内容容器。在执行作者程序时传入更大的 `--arg release_sequence`，随后编译并应用新安装器。

下一章：[语法与构建时执行](/zh/tutorial/syntax/)。
