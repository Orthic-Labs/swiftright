#!/bin/sh
# Usage: pull-win.sh <win-file-under-out> <local-dest>   (text files only; reads through the `win` bridge)
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\\Claude\\sr0o-f1\\scripts\\cat.ps1 -P D:\\Claude\\sr0o-f1\\out\\$1" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$2"
