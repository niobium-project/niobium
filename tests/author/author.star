load("types.star", "literal", "choice")
product(id="reference", release_sequence=1, target=args.get("target", "aarch64-macos"),
        profile="niobium.user.component", primitives={"content.tree": 1, "machine.facts": 1})
root("application")
state_root("application")
library(id="tools", member="libs/tools.wasm", bytes=int(args["library_bytes"]),
        sha256=args["library_sha256"])
input("enabled", choice(True))
input("label", value("string", "Toolchain"))
access = (rights(read=True, write=True), rights(read=True))
grant(id="owned", root="application", primitive="content.tree", version=1,
      max_entries=64, max_bytes=1048576, file_access=access, directory_access=access)
content = value("record", {
    "format": value("enum", "posix-pax-v1"),
    "sha256": value("bytes", b"\x00" * 32),
    "bytes": value("u64", 10240),
})
request = binding("record", {
    "root": literal("application"), "grant": literal("owned"),
    "prefix": literal("toolchain"), "content": binding("literal", content),
    "label": binding("input", "label"), "platform": binding("observation", "machine", fields=["os"]),
    "enabled": binding("input", "enabled"), "previous": binding("previous_state"),
})
observe(id="machine", primitive="machine.facts", version=1, function="facts")
call(id="configure", library="tools", interface="niobium:reference/installer@1.0.0",
     function="build", arguments=[request], grants=["owned"], result_role="plan")
