---
title: 2. 构建第一个安装器
description: 阅读完整 Starlark 产品，输出带类型的模型，组装安装器，再检查部署后的文件。
---

将示例编译成 `setup`，安装到空目录，然后读取 `README.txt`。从[准备工具与项目](/zh/tutorial/setup/)继续，使用同一个 shell，并保持在检出目录的根目录。

## 阅读产品代码

打开 `$TUTORIAL_WORK/source/product.star`。以下是完整的作者程序：

```python
load("inputs.star", "TARGET", "PROFILE", "PRIMITIVES", "FILES_SHA256", "FILES_BYTES",
     "CONTENT_SHA256", "CONTENT_DIGEST", "CONTENT_BYTES")

product(id="example.tutorial", release_sequence=int(args.get("release_sequence", "1")),
        model_version=1, target=TARGET, profile=PROFILE, primitives=PRIMITIVES)
root("application", scope="user")
state_root("application")
library(id="files", member="libs/files.wasm", sha256=FILES_SHA256, bytes=FILES_BYTES)
container(id="content", member="content/hello.tar", sha256=CONTENT_SHA256, bytes=CONTENT_BYTES)
input("enabled", value("bool", True))
access = (rights(read=True, write=True), rights(read=True))
grant(id="owned", root="application", primitive="content.tree", version=1,
      max_entries=16, max_bytes=1048576, file_access=access, directory_access=access)

owner = value("record", {"read": value("bool", True), "write": value("bool", True),
                         "execute": value("bool", False)})
everyone = value("record", {"read": value("bool", True), "write": value("bool", False),
                            "execute": value("bool", False)})
file_access = value("record", {"schema": value("u32", 1), "kind": value("enum", "file"),
                               "owner": owner, "everyone": everyone})
directory_access = value("record", {
    "schema": value("u32", 1), "kind": value("enum", "directory"),
    "owner": owner, "everyone": everyone,
})
content = value("record", {"format": value("enum", "posix-pax-v1"),
                           "sha256": value("bytes", CONTENT_DIGEST),
                           "bytes": value("u64", CONTENT_BYTES)})
request = binding("record", {
    "root": binding("literal", value("string", "application")),
    "grant": binding("literal", value("string", "owned")),
    "prefix": binding("literal", value("string", "hello")),
    "content": binding("literal", content),
    "enabled": binding("input", "enabled"),
    "file-access": binding("literal", file_access),
    "directory-access": binding("literal", directory_access),
})
call(id="deploy", library="files", interface="niobium:files/installer@1.0.0",
     function="build", arguments=[request], grants=["owned"], state_version=1,
     result_role="plan")
```

按四组阅读：

1. `load` 导入生成的输入身份。`product` 固定产品 ID、发布序号、模型版本和运行时配置。
2. `library` 声明可执行能力代码。`container` 声明打包的内容。它们的 `member` 路径标识交付映像中的条目。
3. `root` 声明用户范围安装根目录。`state_root` 选择协调安装状态的根目录。`grant` 限制库可请求的内容和访问权限。
4. `request` 绑定库的参数字段。`call` 选择库中固定的 `build` 导出，并将结果标记为期望安装计划。

`enabled` 输入默认为 true。绑定让它成为安装时的选择。发布序号来自 Starlark 工作进程在构建时接收的 `args`。

访问记录请求所有者读写和所有人读取的权限，授权提供相应的上限。第二部分详细解释[值与绑定](/zh/tutorial/values-bindings/)以及[内容权限](/zh/tutorial/content-capabilities/)。

## 执行作者程序

准备工具已将此源码复制到发布版本 1，并在旁边生成 `inputs.star`。执行该副本：

```sh
zig-out/bin/nb-starlark-v2 \
  --source "$TUTORIAL_WORK/release1/product.star" \
  --out "$TUTORIAL_WORK/release1/product.program.json" \
  --source-map "$TUTORIAL_WORK/release1/product.sources.json" \
  --arg release_sequence=1
```

`product.program.json` 是生成的机器数据。`product.sources.json` 将声明映射回源码位置，用于诊断。工作进程以独占创建方式写出这些文件；重复执行命令时，使用新的输出名称。

## 组装安装器

将生成的模型和锁定输入文件传给编译器：

```sh
zig-out/bin/nb-builder compile \
  --program "$TUTORIAL_WORK/release1/product.program.json" \
  --source-map "$TUTORIAL_WORK/release1/product.sources.json" \
  --lock "$TUTORIAL_WORK/release1/inputs.lock.json" \
  --runtime runtime --runtime-metadata runtime-metadata --worker worker \
  --input "runtime=$TUTORIAL_WORK/release1/runtime" \
  --input "runtime-metadata=$TUTORIAL_WORK/release1/runtime-metadata" \
  --input "worker=$TUTORIAL_WORK/release1/worker" \
  --input "files=$TUTORIAL_WORK/release1/files" \
  --input "content=$TUTORIAL_WORK/release1/content" \
  --input "fallback=$TUTORIAL_WORK/release1/fallback" \
  --signer signer --input "signer=$TUTORIAL_WORK/release1/signer" \
  --output "$TUTORIAL_WORK/release1/setup"
```

编译器根据锁文件验证捕获的输入，验证能力接口和参数类型，并打包预编译运行时。在 macOS 上，锁定的签名工具对最终映像字节签名。

此命令使用第一章准备的 macOS 运行时。当前 PE/ELF 组装配置省略两个签名工具选项；使用这些配置需要对应目标的运行时输入，以及单独的执行资格验证。

## 安装并检查文件

创建产品专用的空目录：

```sh
mkdir "$TUTORIAL_WORK/installation"
"$TUTORIAL_WORK/release1/setup" install \
  --root "application=$TUTORIAL_WORK/installation"
"$TUTORIAL_WORK/release1/setup" status \
  --root "application=$TUTORIAL_WORK/installation"
cat "$TUTORIAL_WORK/installation/current/hello/README.txt"
```

文件内容为：

```text
Hello from the Niobium DSL tutorial, release 1.
```

产品声明逻辑名称 `application`，`--root` 提供它的绝对物理路径。运行时只接管不存在或为空的未拥有根目录，因此请使用专用教程目录。

`current` 指向已发布代的内容。`hello` 前缀来自库请求。运行时在 `.niobium-v2/` 下单独保存所有权和事务数据；目录布局由[生命周期契约](https://github.com/niobium-project/niobium/blob/main/docs/spec/runtime-lifecycle.md)规定。

## 练习：找到安装路径

哪个声明能将 `current/hello/README.txt` 改为 `current/docs/README.txt`？

将请求中的 `prefix` 字面量由 `hello` 改为 `docs`。根目录 ID 仍选择部署根目录，内容容器仍提供 `README.txt`。在新的构建目录和安装根目录中尝试源码修改。

下一章：[配置、更新与卸载](/zh/tutorial/configure-update-remove/)。
