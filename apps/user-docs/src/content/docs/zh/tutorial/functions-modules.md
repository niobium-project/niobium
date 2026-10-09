---
title: '7. 函数与模块'
description: 用辅助函数和 load 语句组织作者代码，同时保留规范化产品模型。
---

你可以把产品构造移入函数和模块，而不改变安装器模型。比较生成的字节，可以检查组织代码的修改是否保留行为。

本章把教程产品提取到模块中，并验证等价性。使用准备好的第 1 次发布目录，以及[第一部分](/zh/tutorial/setup/)的 shell 变量。命令从 Niobium 仓库目录运行。

## 用函数处理源码重复

辅助函数可以构造经常使用的绑定：

```python
def literal_string(text):
    return binding("literal", value("string", text))
```

在请求 record 中，以下表达式等价：

```python
"root": binding("literal", value("string", "application")),
"root": literal_string("application"),
```

为这个字段选择一个表达式，不要声明重复的键。函数在作者求值时运行，返回带类型的绑定。模型不会把它保存为函数。

创建带类型的值需要先有产品上下文。可以先定义辅助函数，但在辅助函数构造 `value()` 或 `binding()` 之前，要先调用 `product()`。产品本身必须恰好创建一次。

## 把构造移到模块

准备目录已包含完整的替代入口 `product_modular.star`：

```python
load("model.star", "make_product")

make_product(int(args.get("release_sequence", "1")))
```

[完整的 `model.star`](https://github.com/niobium-project/niobium/blob/main/examples/dsl-tutorial/model.star)把基线声明放在 `make_product(release_sequence)` 中。它在模块顶层加载生成的身份常量，然后在入口调用函数时构造产品：

```python
load("inputs.star", "TARGET", "PROFILE", "PRIMITIVES", "FILES_SHA256", "FILES_BYTES",
     "CONTENT_SHA256", "CONTENT_DIGEST", "CONTENT_BYTES")

def make_product(release_sequence):
    product(id="example.tutorial", release_sequence=release_sequence,
            model_version=1, target=TARGET, profile=PROFILE, primitives=PRIMITIVES)
    root("application", scope="user")
    state_root("application")
    # The remaining declarations are in the complete module.
```

`load("model.star", "make_product")` 导入命名符号，不会调用函数。把构造放在函数内，可以避免导入模块时顺带创建产品。

作者根目录是 `--source` 所指定入口文件的所在目录。模块路径相对于这个根目录，嵌套模块中的 load 也如此，不会切换为加载模块自己的目录。例如，`release1/` 中的入口会从 `release1/lib/policy.star` 加载 `lib/policy.star`；该模块内部的 load 仍从 `release1/` 开始。

Starlark 会冻结已加载模块的全局值。应导出函数和不可变数据，不要依赖导入后修改共享字典。worker 在单次求值中缓存模块，并拒绝加载循环、绝对路径和在路径语法上超出作者根目录的路径。模块与执行预算见 [Authoring v2](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring.md#starlark-api)。

## 练习：验证提取

用相同的准备输入求值平铺作者和模块化作者，比较规范化输出。在这个练习中，不修改发布序号、默认值、授权或内容身份。

完整答案使用提供的 `product_modular.star` 和 `model.star`：

```sh
"$NIOBIUM_REPO/zig-out/bin/nb-starlark-v2" \
  --source "$TUTORIAL_WORK/release1/product.star" \
  --out "$TUTORIAL_WORK/flat.program.json" \
  --source-map "$TUTORIAL_WORK/flat.sources.json"
"$NIOBIUM_REPO/zig-out/bin/nb-starlark-v2" \
  --source "$TUTORIAL_WORK/release1/product_modular.star" \
  --out "$TUTORIAL_WORK/modular.program.json" \
  --source-map "$TUTORIAL_WORK/modular.sources.json"
cmp "$TUTORIAL_WORK/flat.program.json" "$TUTORIAL_WORK/modular.program.json"
cat "$TUTORIAL_WORK/modular.sources.json"
```

`cmp` 退出码为 0，不产生输出。sidecar 把 `call:deploy` 等声明关联到 `model.star` 中的位置，因此它们的诊断位置与平铺作者不同。源码位置与规范化模型字节分开保存，不会改变产品身份。

如果比较失败，先检查声明差异，再编译安装器。即使在整理源码时发生，修改默认值或函数参数仍是模型变更。

## 选择稳定的边界

用函数复用构造过程，用模块组织相关作者代码。模块文件名组织源码。产品身份、`Call.id`、`Library.id` 和 interface/function 选择信息标识运行时所有权。把 `deploy` 移到另一个文件会保留它的 ID。重命名这个调用会改变所属实例，不是等价重构。

[编译后产品契约](https://github.com/niobium-project/niobium/blob/main/docs/spec/program-image.md#state-and-explicit-migration)定义调用状态所有权与显式迁移。应把这些变更与本章保留字节的源码提取分开处理。

下一章：[编译与诊断](/zh/tutorial/compilation-diagnostics/)。
