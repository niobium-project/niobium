#!/bin/sh
# Git for Windows runs this file. The sibling .cmd script calls zig build.
set -eu
script=$(cygpath -w "$0.cmd")
args=
for arg in "$@"; do
    args="$args \"$arg\""
done
exec cmd.exe //D //C "call \"$script\"$args"
