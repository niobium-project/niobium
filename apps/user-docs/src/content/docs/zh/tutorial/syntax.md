---
title: '4. 语法与构建时执行'
description: 使用变量、集合、函数和条件，在安装器运行之前构造产品。
---

你可以用 Starlark 的编程结构生成产品模型。这些代码在构建期间执行完毕。安装器中包含的是生成后的带类型图，不会运行 Starlark 解释器或求值作者源码。

本章介绍变量、集合、函数和条件构造。请先完成[第一个安装器](/zh/tutorial/first-installer/)。命令从 Niobium 仓库目录运行，并继续使用[准备章节](/zh/tutorial/setup/)中同一个 shell 的 `NIOBIUM_REPO` 和 `TUTORIAL_WORK`。

## 阅读语法

Starlark 用缩进表示代码块。字符串带引号，`True` 和 `False` 是布尔值，`#` 开始注释。赋值为值命名：

```python
prefix = "hello"
enabled = True
release_sequence = 1
```

最先需要了解的集合是列表、元组和字典：

```python
names = ["cli", "examples"]
access = (rights(read=True, write=True), rights(read=True))
defaults = {"cli": True, "examples": False}
```

列表保留元素顺序；字典把键映射到值。元组可以组合固定的两个值，例如授权中的 `(owner, everyone)` 权限对。这些都是普通 Starlark 值。下一章介绍如何用 `value()` 把它们构造为具有精确类型的产品值。

函数以 `def` 开始。语句形式的 `if` 和 `for` 要放在函数中；当前 worker 未启用顶层条件或循环语句。

```python
def default_enabled(include):
    if include:
        return value("bool", True)
    return value("bool", False)
```

调用此函数决定在模型中写入哪个布尔值。它不会创建安装时执行的条件。

## 构造多个输入

创建 `$TUTORIAL_WORK/syntax.star`，写入完整源码：

```python
product(id="example.syntax", release_sequence=1, target="aarch64-macos",
        profile="niobium.user.component", primitives={})

def declare_inputs(names, defaults, include_docs):
    for name in names:
        input(name, value("bool", defaults[name]))
    if include_docs:
        input("docs", value("bool", True))

declare_inputs(["cli", "examples"], {"cli": True, "examples": False},
               args.get("docs", "false") == "true")
```

求值两次，写入两个新文件：

```sh
"$NIOBIUM_REPO/zig-out/bin/niobium-starlark-v2" \
  --source "$TUTORIAL_WORK/syntax.star" \
  --out "$TUTORIAL_WORK/syntax.program.json"
"$NIOBIUM_REPO/zig-out/bin/niobium-starlark-v2" \
  --source "$TUTORIAL_WORK/syntax.star" --arg docs=true \
  --out "$TUTORIAL_WORK/syntax-docs.program.json"
cat "$TUTORIAL_WORK/syntax.program.json"
cat "$TUTORIAL_WORK/syntax-docs.program.json"
```

第一个模型声明 `cli` 和 `examples`；第二个还声明 `docs`。两个命令都会成功退出，不会安装任何文件。这个小模型只演示作者求值，没有内容或能力调用。

`args` 是不可变的字符串字典，由重复的 `--arg KEY=VALUE` 填充。键名和解释方式由作者定义。这里通过与字符串 `"true"` 比较，得到传给函数的布尔值。

## 练习：修改默认值

让 `examples` 默认启用，不增加输入，也不修改它的 ID。把源码求值到 `$TUTORIAL_WORK/syntax-answer.program.json`，检查 `examples` 输入。

完整答案如下：

```python
product(id="example.syntax", release_sequence=1, target="aarch64-macos",
        profile="niobium.user.component", primitives={})

def declare_inputs(names, defaults, include_docs):
    for name in names:
        input(name, value("bool", defaults[name]))
    if include_docs:
        input("docs", value("bool", True))

declare_inputs(["cli", "examples"], {"cli": True, "examples": True},
               args.get("docs", "false") == "true")
```

使用新的输出路径运行第一个求值命令。生成的 `examples` 默认值现在为 true。源码中的循环已经执行完毕，安装器不会再运行这个循环。

## 区分构建与安装

worker 提供 Starlark 和 Niobium 作者内建函数。它不提供 Python 导入、任意文件系统访问或 shell 执行。`load()` 可以在作者根目录内导入有大小限制的源码模块，[函数与模块](/zh/tutorial/functions-modules/)将使用它。

安装期间，输入绑定和宿主观察向固定能力调用提供值。需要在这个阶段执行的产品行为属于能力库，例如 files 库根据 `enabled` 决定是否部署内容。

作者 API 和 worker 限制见 [Authoring v2](https://github.com/niobium-project/niobium/blob/main/docs/development/authoring-v2.md)。

下一章：[值、绑定与安装输入](/zh/tutorial/values-bindings/)。
