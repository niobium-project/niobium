---
title: '6. 内容、权限与能力调用'
description: 连接内容身份、逻辑根目录、访问授权、Component 调用、结果依赖与宿主观察。
---

能力库提出产品的期望资源。宿主检查内容、权限和访问策略，然后冻结事务。声明归档或加载库本身不会授权机器变更。

本章解释教程中的声明，再加入真实的结果依赖和宿主观察。继续使用[第一部分](/zh/tutorial/setup/)的 `NIOBIUM_REPO` 和 `TUTORIAL_WORK`；命令使用该部分验证过的 macOS arm64 SDK。

## 认识各个对象

产品包含一组相互独立的对象：

| 声明 | 教程 ID | 用途 |
|---|---|---|
| `root()` | `application` | 逻辑所有权锚点，通过 `--root` 绑定到本机目录 |
| `state_root()` | `application` | 协调持久安装状态的根目录 |
| `container()` | `content` | 由散列和字节长度确定身份的固定规范内容 |
| `library()` | `files` | 导出文件部署函数的固定 Component |
| `grant()` | `owned` | 此根目录上 `content.tree` 的权限及资源上限 |
| `call()` | `deploy` | 库中 `build` 函数的一个调用实例 |

`libs/files.wasm` 和 `content/hello.tar` 等 `member` 值是安装器载荷中的成员名称，不是安装路径。根目录与请求的 `prefix="hello"` 共同确定所提出的 `README.txt` 放在哪里。

准备工具把 `payload/README.txt` 编码为规范 POSIX pax 内容。`container()` 声明其身份；请求中的带类型 `content` record 向库传入相同身份。编译器输入锁文件另行固定组装安装器时使用的源字节。规范化与身份规则见[内容契约](https://github.com/niobium-project/niobium/blob/main/docs/spec/content-container.md)。

## 授权上限与期望访问策略

基线授权允许有上限的文件部署：

```python
access = (rights(read=True, write=True), rights(read=True))
grant(id="owned", root="application", primitive="content.tree", version=1,
      max_entries=16, max_bytes=1048576,
      file_access=access, directory_access=access)
```

`rights()` 构造授权的权限位。元组的第一个元素是所有者的上限，第二个是所有人的上限。调用只有声明 `grants=["owned"]` 才会获得此权限。

files 库还接收显式的期望策略，它是带类型的 WIT record：

```python
owner = value("record", {
    "read": value("bool", True),
    "write": value("bool", True),
    "execute": value("bool", False),
})
everyone = value("record", {
    "read": value("bool", True),
    "write": value("bool", False),
    "execute": value("bool", False),
})
file_access = value("record", {
    "schema": value("u32", 1), "kind": value("enum", "file"),
    "owner": owner, "everyone": everyone,
})
```

目录策略的 `kind="directory"`，权限相同。两者使用精确的 WIT 字段名 `file-access` 和 `directory-access` 放入请求。期望策略必须在授权上限之内。归档 mode `0644` 是内容元数据，不会授予安装后的访问权。这个可移植策略中，目录的 `execute` 必须为 false。本机映射和拒绝规则见 [Portable access policy](https://github.com/niobium-project/niobium/blob/main/docs/spec/access-policy.md)。

## 值与计划

基线使用固定的函数选择信息，请求一个计划：

```python
call(id="deploy", library="files", interface="niobium:files/installer@1.0.0",
     function="build", arguments=[request], grants=["owned"],
     state_version=1, result_role="plan")
```

[files WIT 接口](https://github.com/niobium-project/niobium/blob/main/api/wit/files/files.wit)定义 `build` 返回 `result<plan, string>`。成功计划提出容器和可选私有状态；错误会终止求值。宿主检查提案并冻结操作。恢复直接使用持久计划，不会重新执行 Starlark 或库。

`result_role="value"` 是默认值，这类调用把带类型的结果提供给其他调用。用 `binding("node_result", "source")` 引用它会自动创建依赖。如果没有结果绑定来表达依赖，可用 `after=["source"]` 增加顺序约束。引用必须存在，循环依赖会被拒绝；源码中的声明顺序不是运行时调度顺序。

## 读取宿主观察

观察声明一个带版本的只读宿主函数：

```python
observe(id="machine", primitive="machine.facts", version=1, function="facts")
```

流程示例把观察结果 record 中的 `os` 字段绑定为部署前缀：

```python
"prefix": binding("observation", "machine", fields=["os"]),
```

`fields` 是按顺序选择 record 字段的投影路径，不是表达式字符串。组装安装器的目标在构建时固定；这个观察在运行时求值图时读取机器。在本教程流程中，它产生 `macos`。

## 练习：选择备用内容

使用[完整的流程作者源码](https://github.com/niobium-project/niobium/blob/main/examples/dsl-tutorial/product_flow.star)。它声明主内容和备用内容，增加 `primary` 输入，并调用 files 库的纯函数导出 `select-content`：

```python
call(id="source", library="files", interface="niobium:files/installer@1.0.0",
     function="select-content", arguments=[binding("literal", content),
     binding("literal", fallback), binding("input", "primary")])

# Inside deploy's complete request:
"content": binding("node_result", "source"),
"prefix": binding("observation", "machine", fields=["os"]),
```

使用未修改的仓库示例，在新目录中构建这个模型：

```sh
FLOW_BUILD="$TUTORIAL_WORK/flow"
"$NIOBIUM_REPO/zig-out/bin/niobium-tutorial-prepare" \
  --sdk "$NIOBIUM_REPO/zig-out" \
  --source "$NIOBIUM_REPO/examples/dsl-tutorial" --out "$FLOW_BUILD"
"$NIOBIUM_REPO/zig-out/bin/nb-starlark-v2" \
  --source "$FLOW_BUILD/product_flow.star" \
  --out "$FLOW_BUILD/product.program.json" \
  --source-map "$FLOW_BUILD/product.sources.json"
"$NIOBIUM_REPO/zig-out/bin/nb-builder" compile \
  --program "$FLOW_BUILD/product.program.json" \
  --source-map "$FLOW_BUILD/product.sources.json" \
  --lock "$FLOW_BUILD/inputs.lock.json" \
  --runtime runtime --runtime-metadata runtime-metadata --worker worker \
  --input "runtime=$FLOW_BUILD/runtime" \
  --input "runtime-metadata=$FLOW_BUILD/runtime-metadata" \
  --input "worker=$FLOW_BUILD/worker" --input "files=$FLOW_BUILD/files" \
  --input "content=$FLOW_BUILD/content" --input "fallback=$FLOW_BUILD/fallback" \
  --signer signer --input "signer=$FLOW_BUILD/signer" \
  --output "$FLOW_BUILD/hello.setup"
```

安装时选择备用内容。完整答案继续如下：

```sh
FLOW_ROOT="$TUTORIAL_WORK/flow-installation"
mkdir "$FLOW_ROOT"
"$FLOW_BUILD/hello.setup" install \
  --root "application=$FLOW_ROOT" --set primary=false
cmp "$NIOBIUM_REPO/examples/dsl-tutorial/fallback/README.txt" \
  "$FLOW_ROOT/current/macos/README.txt"
"$FLOW_BUILD/hello.setup" reconfigure \
  --root "application=$FLOW_ROOT" --set primary=true
cmp "$NIOBIUM_REPO/examples/dsl-tutorial/payload/README.txt" \
  "$FLOW_ROOT/current/macos/README.txt"
"$FLOW_BUILD/hello.setup" uninstall --root "application=$FLOW_ROOT"
```

两个比较都以 0 退出，不产生输出。相同安装器通过 `source` 结果选择两个不同的内容身份，并从宿主观察读取前缀。选择不会获取任意文件：两个容器都在安装前声明并嵌入。

这个流程模型使用独立安装根目录，因为它的图与基线不同。不要把相同发布序号下修改过的图，当成已有安装的新发布。

下一章：[函数与模块](/zh/tutorial/functions-modules/)。
