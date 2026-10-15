#!/bin/sh
# usage: setframe.sh <n> [out dir] : a Sandbox `command` job that sets the guest's launch counter (C:\work\hub-frame.txt) to n
set -eu
python3 /Volumes/D/claude/swiftright/factory/tools/sandbox/client.py command "New-Item -ItemType Directory -Force C:\\work | Out-Null; [IO.File]::WriteAllText(\"C:\\work\\hub-frame.txt\",\"$1\"); \"set \" + [IO.File]::ReadAllText(\"C:\\work\\hub-frame.txt\")" --out "${2:-/tmp/setframe-out}" | tail -2
