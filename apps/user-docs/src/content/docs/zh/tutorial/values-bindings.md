---
title: '5. 值、绑定与安装输入'
description: 区分源码值、精确的 WIT 值、参数绑定、构建参数与安装输入。
---

用 `value()` 构造带类型的数据，用 `binding()` 指定调用参数的来源。即使 Starlark 程序已经执行完毕，绑定仍可以保留安装期间的选择。

本章解释值的几个层次和两种输入。继续使用[第一部分](/zh/tutorial/setup/)的 shell 和第 1 次发布文件。所有命令从 Niobium 仓库目录运行。

## 值的三个层次

教程中的 `enabled` 字段涉及三个层次：

| 层次 | 示例 | 含义 |
|---|---|---|
| Starlark 值 | `True` | 求值源码时使用的布尔值 |
| 带类型的产品值 | `value("bool", True)` | 作为输入默认值保存的精确布尔值 |
| 参数绑定 | `binding("input", "enabled")` | 求值运行时图时读取选择的输入值 |

分别声明默认值和参数绑定：

```python
input("enabled", value("bool", True))

# Inside the request record passed to files.build:
"enabled": binding("input", "enabled"),
```

如果把请求中的这个字段改为 `binding("literal", value("bool", True))`，无论选择哪个输入值，它都会传入 true。

## 构造精确类型的数据

WebAssembly Interface Types（WIT）描述 Component 导出的参数和结果类型。Niobium 保留这些类型。整数宽度有意义：即使都包含 `1`，`u32` 和 `u64` 仍是不同类型。

以下表达式可以在 `product()` 创建作者上下文后使用：

```python
enabled = value("bool", True)
length = value("u64", 10240)
title = value("string", "Hello")
format = value("enum", "posix-pax-v1")
digest = value("bytes", b"\x00" * 32)
content = value("record", {
    "format": format,
    "sha256": digest,
    "bytes": length,
})
```

这里的全零散列只演示字节值。可运行的产品使用根据实际规范内容生成的 `CONTENT_DIGEST` 和 `CONTENT_BYTES`。十六进制字符串与 32 个原始散列字节是不同的值。

复合值的元素是带类型的值，而不是普通 Starlark 元素。例如，`value("list", [value("string", "Hello")])` 是一个带类型的列表。API 还提供元组、variant、option、result 和 flags，构造器细节见 [Authoring v2](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring-v2.md#starlark-api)。

带类型的 record 是固定数据。record 绑定可以组合不同来源：

```python
request = binding("record", {
    "content": binding("literal", content),
    "enabled": binding("input", "enabled"),
})
```

这个片段只演示组合方式。files 库的完整请求还包含 root、grant、prefix 和两个访问策略，见 `product.star`。

## 构建参数与安装输入

`--arg` 向作者提供不可变字符串。`--set` 向安装器提供标量输入值。相同的名称不会自动连接二者：

| 选择 | 读取时机 | 效果 |
|---|---|---|
| `--arg release_sequence=2` | 作者求值 | 教程用 `int()` 转换字符串，生成第 2 次发布 |
| `--arg enabled=false` | 作者求值 | 无效果，因为 `product.star` 不读取这个键 |
| `--set enabled=false` | 安装或重配置 | 输入绑定向 `files.build` 传入 false |

不修改安装器，验证中间一行：

```sh
"$NIOBIUM_REPO/zig-out/bin/niobium-starlark-v2" \
  --source "$TUTORIAL_WORK/release1/product.star" \
  --arg enabled=false --out "$TUTORIAL_WORK/values-args.program.json"
cmp "$TUTORIAL_WORK/release1/product.program.json" \
  "$TUTORIAL_WORK/values-args.program.json"
```

`cmp` 退出码为 0，不产生输出。作者生成的模型仍包含 true 默认值。

## 练习：保留默认值，选择 false

安装第 1 次发布时禁用内容，再不经过重新构建就启用它。使用独立根目录，避免修改第一部分的安装。

完整答案如下：

```sh
VALUES_ROOT="$TUTORIAL_WORK/values-installation"
mkdir "$VALUES_ROOT"
"$TUTORIAL_WORK/release1/setup" install \
  --root "application=$VALUES_ROOT" --set enabled=false
test ! -e "$VALUES_ROOT/current/hello/README.txt"
"$TUTORIAL_WORK/release1/setup" reconfigure \
  --root "application=$VALUES_ROOT" --set enabled=true
cmp "$NIOBIUM_REPO/examples/dsl-tutorial/payload/README.txt" \
  "$VALUES_ROOT/current/hello/README.txt"
"$TUTORIAL_WORK/release1/setup" uninstall \
  --root "application=$VALUES_ROOT"
```

第一个检查成功，因为 false 不会产生期望内容。第二个检查成功，因为重配置向相同的编译后输入绑定传入 true。两个操作都不会求值 Starlark。

## 默认值与完整输入类型

编译器根据绑定实际使用处的 WIT 参数解析输入的完整类型。它会检查默认值，并拒绝相互冲突的使用方式。enum 的默认分支不会把取值范围限制为单个分支。

未使用的布尔值、整数或类型完整的 record 可以提供足够的类型推断信息。未使用的空泛型列表、缺失值的 option、enum、flags、variant 或 result 则不能。例如，`input("unused", value("list", []))` 可以生成作者 IR，但编译时会以 `InputTypeAmbiguous` 失败。把这类输入绑定到真实的带类型参数，不要自行编造序列化类型字段。输入覆盖值和保存的输入都会根据编译器解析出的类型检查。

规则见 [Parameter types](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring-v2.md#parameter-types)，类型错误实验见[编译与诊断](/zh/tutorial/compilation-diagnostics/)。

下一章：[内容、权限与能力调用](/zh/tutorial/content-capabilities/)。
