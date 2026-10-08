def environment(library, version):
    input("sdk", "stable")
    resource("environment", "toolchain.env")
    instance("environment", library, state_version = version,
             inputs = ["sdk"], resources = ["environment"])
    if version == 2:
        for owner in ["", "environment"]:
            migration("upgrade-1-2", 1, 2, owner = owner)
