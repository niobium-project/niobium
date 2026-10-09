---
title: '8. 编译与诊断'
description: 理解作者 IR、锁定输入与本机组装的关系，并诊断类型和内容身份错误。
---

编译器把带类型的产品与精确锁定的输入、完整预编译运行时结合起来。绑定诊断指出失败阶段和对象；提供作者 sidecar 时，还会包含源码位置。

本章解释构建制品，并重现两个不会改变安装的错误。使用[第一部分](/zh/tutorial/setup/)的 shell 变量和 macOS arm64 SDK。命令从 Niobium 仓库目录运行。

## 理解构建制品

| 准备目录中的文件 | 作用 |
|---|---|
| `product.star`、加载的 `.star` 模块 | 在构建主机求值的作者源码 |
| `inputs.star` | 包含实际身份和运行时配置的生成源码常量 |
| `product.program.json` | 前端生成的规范化作者 IR |
| `product.sources.json` | 可选源码映射 sidecar，与语义模型身份分开 |
| `inputs.lock.json` | 精确的源类型、版本、长度、散列和依赖 |
| `runtime`、`runtime-metadata` | 完整运行时模板和独立锁定的发布元数据 |
| `files` | 固定的官方 files Component |
| `content`、`fallback` | 为示例准备的规范内容容器 |
| `worker`、`signer` | 锁定的检查工具，以及 macOS 上的最终签名工具 |
| `hello.setup` | 包含运行时、编译后产品和载荷的最终本机安装器 |

产品 `.json` 是编译器传输格式，不是手工编写的配置文件。编译器解析完整 WIT 输入类型，验证权限与依赖，捕获固定输入，规范化内容，再组装镜像。它保留模板中的可执行代码，不会重新链接或执行目标运行时。

原始源字节和规范内容具有独立身份，即使本示例提供的容器已经规范化。运行时、元数据、库、编译后产品和最终安装器也分别具有身份。散列一致证明你持有的是哪些字节；可信获取建立这些字节的提供者身份。这个从源码构建的练习不会建立外部发布者的权限。

完整流程见 [Compiler and frontends v2](https://github.com/niobium-project/niobium/blob/main/docs/spec/compiler-frontends-v2.md) 和 [Locked compiler inputs](https://github.com/niobium-project/niobium/blob/main/docs/spec/compiler-inputs-v1.md)。

## 区分前端与编译器错误

格式不正确的带类型值可能在作者求值期间失败。例如，把基线默认值改成以下表达式，会产生 `Error in value: bool required`：

```python
input("enabled", value("bool", "yes"))
```

要用 `True` 构造布尔值，而不是字符串。前端会包含 Starlark 调用位置；这个求值错误不会生成模型。

格式正确的带类型值，仍可能与库参数的类型不同。下面的实验成功构造字符串，然后在编译器根据库的 `bool` 字段检查绑定时失败。

## 练习：定位使用处类型错误

准备独立输入，只修改默认值的类型：

```sh
DIAG_BUILD="$TUTORIAL_WORK/diagnostics"
"$NIOBIUM_REPO/zig-out/bin/niobium-tutorial-prepare" \
  --sdk "$NIOBIUM_REPO/zig-out" \
  --source "$NIOBIUM_REPO/examples/dsl-tutorial" --out "$DIAG_BUILD"
sed 's/input("enabled", value("bool", True))/input("enabled", value("string", "true"))/' \
  "$DIAG_BUILD/product.star" > "$DIAG_BUILD/bad-type.star"
"$NIOBIUM_REPO/zig-out/bin/niobium-starlark-v2" \
  --source "$DIAG_BUILD/bad-type.star" \
  --out "$DIAG_BUILD/bad-type.program.json" \
  --source-map "$DIAG_BUILD/bad-type.sources.json"
```

作者求值成功。编译生成的模型：

```sh
"$NIOBIUM_REPO/zig-out/bin/niobium-compiler-v2" compile \
  --program "$DIAG_BUILD/bad-type.program.json" \
  --source-map "$DIAG_BUILD/bad-type.sources.json" \
  --lock "$DIAG_BUILD/inputs.lock.json" \
  --runtime runtime --runtime-metadata runtime-metadata --worker worker \
  --input "runtime=$DIAG_BUILD/runtime" \
  --input "runtime-metadata=$DIAG_BUILD/runtime-metadata" \
  --input "worker=$DIAG_BUILD/worker" --input "files=$DIAG_BUILD/files" \
  --input "content=$DIAG_BUILD/content" --input "fallback=$DIAG_BUILD/fallback" \
  --signer signer --input "signer=$DIAG_BUILD/signer" \
  --output "$DIAG_BUILD/hello.setup"
```

命令退出码为 1。诊断包含以下字段，以及 `bad-type.star` 中 `deploy` 调用的实际位置：

```json
{
  "stage": "binding",
  "code": "type_mismatch",
  "object": "deploy",
  "kind": "call",
  "cause": "WitTypeMismatch"
}
```

源码位置指向参数未通过 WIT 验证的调用。沿其 `enabled` 绑定找到输入默认值。完整修正就是原来的声明：

```python
input("enabled", value("bool", True))
```

未修改的 `product.star` 已包含这个答案。将它生成到新文件，再构建：

```sh
"$NIOBIUM_REPO/zig-out/bin/niobium-starlark-v2" \
  --source "$DIAG_BUILD/product.star" \
  --out "$DIAG_BUILD/good.program.json" \
  --source-map "$DIAG_BUILD/good.sources.json"
"$NIOBIUM_REPO/zig-out/bin/niobium-compiler-v2" compile \
  --program "$DIAG_BUILD/good.program.json" \
  --source-map "$DIAG_BUILD/good.sources.json" \
  --lock "$DIAG_BUILD/inputs.lock.json" \
  --runtime runtime --runtime-metadata runtime-metadata --worker worker \
  --input "runtime=$DIAG_BUILD/runtime" \
  --input "runtime-metadata=$DIAG_BUILD/runtime-metadata" \
  --input "worker=$DIAG_BUILD/worker" --input "files=$DIAG_BUILD/files" \
  --input "content=$DIAG_BUILD/content" --input "fallback=$DIAG_BUILD/fallback" \
  --signer signer --input "signer=$DIAG_BUILD/signer" \
  --output "$DIAG_BUILD/hello.setup"
```

编译器以 0 退出，输出包含 `status="ok"` 的 JSON 报告。每个锁定输入都需要 `--input` 映射，包括基线没有使用的准备后备用内容。

## 练习：失败时保留已有输出

保存有效安装器和内容，然后不更新锁文件，直接改变内容源：

```sh
cp "$DIAG_BUILD/hello.setup" "$DIAG_BUILD/hello.saved"
cp "$DIAG_BUILD/content" "$DIAG_BUILD/content.saved"
printf x >> "$DIAG_BUILD/content"
```

再次运行上面的成功编译命令，使用 `good.program.json` 和相同输出路径。这次退出码为 1，输出 `error: LockMismatch`。错误发生在捕获输入期间，此时还未填充详细对象诊断，JSON 错误报告中的 `diagnostic: null`。

这个故意破坏输入的实验，其完整恢复步骤是：

```sh
cmp "$DIAG_BUILD/hello.saved" "$DIAG_BUILD/hello.setup"
cp "$DIAG_BUILD/content.saved" "$DIAG_BUILD/content"
cmp "$DIAG_BUILD/content.saved" "$DIAG_BUILD/content"
```

两个比较都以 0 退出，不产生输出。失败构建保留了之前发布的安装器，源也已恢复。没有运行运行时命令，因此实验不会改变安装。真实内容更新应通过准备过程重新生成身份和锁文件，再构建新的发布，见[配置、更新与卸载](/zh/tutorial/configure-update-remove/)。

## 输出所有权与兼容性

准备工具要求使用新目标目录。Starlark 前端以独占方式创建模型和可选 sidecar；再次求值时应使用新文件名。如果文件名已存在，选择新名称，不要把拒绝创建当成语言错误。编译器只有完成验证和所需最终签名后才发布组装镜像；发布可以替换已有安装器。

教程中只改变内容的第 2 次发布保留 `model_version=1`、`Call.id="deploy"` 和 `state_version=1`，同时递增 `release_sequence`。模型转换与调用状态转换具有独立兼容性声明。不要通过递增版本或重命名调用来编造兼容性。[迁移契约](https://github.com/niobium-project/niobium/blob/main/docs/spec/migration-v2.md)定义高级场景。

提供的 macOS finalizer 覆盖 ad-hoc 测量配置。生产发布者签名和平台资格验收需要各自的流程与证据；教程编译成功不能建立这些结论。记录的范围见[状态与平台](/zh/status/)。

返回[教程总览](/zh/tutorial/)，或通过 [Authoring v2](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring-v2.md)继续学习完整 API。
