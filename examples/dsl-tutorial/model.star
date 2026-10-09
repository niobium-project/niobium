load("inputs.star", "TARGET", "PROFILE", "PRIMITIVES", "FILES_SHA256", "FILES_BYTES",
     "CONTENT_SHA256", "CONTENT_DIGEST", "CONTENT_BYTES")


def make_product(release_sequence):
    product(id="example.tutorial", release_sequence=release_sequence,
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
