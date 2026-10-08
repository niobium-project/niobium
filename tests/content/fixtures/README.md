# Independent pax vectors

Both archives describe the same six entries: directories `bin`, `empty` and
the directory named by Unicode code points `U+8CC7 U+6599`; executable `bin/tool` (mode `0755`, bytes `#!/bin/sh\nexit 0\n`);
`bin/alias` (symbolic-link text `./tool`); and that directory followed by `/long-` followed by 110 `a`
characters (mode `0640`, bytes `payload\0bytes\n`). Directories use mode `0755`.

| File | Producer | Source SHA-256 |
|---|---|---|
| `gnu-pax.tar` | GNU tar 1.35 on Linux x86_64 | `850f2b5507a76a9c459cf54b69bab4b42f4dc91d0ae8ba4666bfa213f7499cfe` |
| `libarchive-pax.tar` | bsdtar 3.5.3, libarchive 3.7.4 on macOS arm64 | `3371996bbb547cf57d779b442ff26d04721daed4a94be08a14ee9cfd26d3aa53` |

The producer commands are:

```sh
tar --format=pax --sort=name -cf gnu-pax.tar -C input .
COPYFILE_DISABLE=1 bsdtar --format=pax --no-xattrs --no-acls --no-fflags \
  -cf libarchive-pax.tar -C input .
```

Source ownership, timestamp metadata and record ordering differ. The canonical
uncompressed stream is 11264 bytes with SHA-256
`e52575e52af743e4860ccfdfa3517d336b52b1fd3f749af93bcdf9ce32cd4b80`.
The fixtures are independently produced inputs, not compiler snapshots to update.

`tests/content/main.zig` consumes an input tar path and an output path. Its output
can be listed and extracted by GNU tar and bsdtar for reverse interoperability.
