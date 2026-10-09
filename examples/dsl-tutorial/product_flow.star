load("inputs.star", "TARGET", "PROFILE", "PRIMITIVES", "FILES_SHA256", "FILES_BYTES",
     "CONTENT_SHA256", "CONTENT_DIGEST", "CONTENT_BYTES",
     "FALLBACK_SHA256", "FALLBACK_DIGEST", "FALLBACK_BYTES")

product(id="example.tutorial", release_sequence=int(args.get("release_sequence", "1")),
        model_version=1, target=TARGET, profile=PROFILE, primitives=PRIMITIVES)
root("application", scope="user")
state_root("application")
library(id="files", member="libs/files.wasm", sha256=FILES_SHA256, bytes=FILES_BYTES)
container(id="content", member="content/hello.tar", sha256=CONTENT_SHA256, bytes=CONTENT_BYTES)
container(id="fallback", member="content/fallback.tar", sha256=FALLBACK_SHA256,
          bytes=FALLBACK_BYTES)
input("enabled", value("bool", True))
input("primary", value("bool", True))
observe(id="machine", primitive="machine.facts", version=1, function="facts")
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
fallback = value("record", {"format": value("enum", "posix-pax-v1"),
                            "sha256": value("bytes", FALLBACK_DIGEST),
                            "bytes": value("u64", FALLBACK_BYTES)})
call(id="source", library="files", interface="niobium:files/installer@1.0.0",
     function="select-content", arguments=[binding("literal", content),
     binding("literal", fallback), binding("input", "primary")])
request = binding("record", {
    "root": binding("literal", value("string", "application")),
    "grant": binding("literal", value("string", "owned")),
    "prefix": binding("observation", "machine", fields=["os"]),
    "content": binding("node_result", "source"),
    "enabled": binding("input", "enabled"),
    "file-access": binding("literal", file_access),
    "directory-access": binding("literal", directory_access),
})
call(id="deploy", library="files", interface="niobium:files/installer@1.0.0",
     function="build", arguments=[request], grants=["owned"], state_version=1,
     result_role="plan")
