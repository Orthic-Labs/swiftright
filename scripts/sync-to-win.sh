#!/bin/sh
# Copy a local directory's files to a Windows directory through the `win` bridge (small source trees only).
# Usage: scripts/sync-to-win.sh <local-dir> <windows-dir>
set -eu
src=$1; dst=$2
b64=$(tar -czf - -C "$src" --exclude .build --exclude target . | base64 | tr -d '\n')
[ ${#b64} -lt 24000 ] || { echo "sync-to-win: archive too large (${#b64} b64 chars)" >&2; exit 1; }
win "\$d='$dst'; New-Item -ItemType Directory -Force \$d | Out-Null; \$t=Join-Path \$env:TEMP ('sync-'+[guid]::NewGuid()+'.tgz'); [IO.File]::WriteAllBytes(\$t,[Convert]::FromBase64String('$b64')); tar -xzf \$t -C \$d; Remove-Item \$t; Get-ChildItem -Recurse -File \$d | Where-Object { \$_.FullName -notmatch '\\\\.build\\\\' } | Measure-Object | ForEach-Object { 'synced files: ' + \$_.Count }"
