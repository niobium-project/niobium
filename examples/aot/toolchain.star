load("common.star", "environment")

product("example.toolchain", model_version, model_version)
library("environment", read_blob(library_path))
environment("environment", model_version)
