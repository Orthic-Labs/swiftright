#!/bin/sh
# Copy a local directory's files to a Windows directory through the `win` bridge, in chunks.
# Usage: scripts/sync-to-win.sh <local-dir> <windows-dir>
set -eu
src=$1; dst=$2
b64=$(tar -czf - -C "$src" --exclude .build --exclude target --exclude .swiftpm . | base64 | tr -d '\n')
id=$(date +%s)-$$
tmp="\$env:TEMP\\sync-$id.b64"
chunk=20000; off=0; len=${#b64}
while [ "$off" -lt "$len" ]; do
  part=$(printf %s "$b64" | cut -c$((off+1))-$((off+chunk)))
  win "Add-Content -NoNewline -Path $tmp -Value '$part'" >/dev/null
  off=$((off+chunk))
done
win "\$d='$dst'; New-Item -ItemType Directory -Force \$d | Out-Null; \$t=\$env:TEMP+'\\sync-$id.tgz'; [IO.File]::WriteAllBytes(\$t,[Convert]::FromBase64String((Get-Content -Raw $tmp))); tar -xzf \$t -C \$d; Remove-Item \$t,$tmp; Get-ChildItem -Recurse -File \$d | Where-Object { \$_.FullName -notmatch '\\\\.build\\\\' } | Measure-Object | ForEach-Object { 'synced files: ' + \$_.Count }"
