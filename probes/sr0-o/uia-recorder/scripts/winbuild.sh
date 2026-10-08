#!/bin/sh
# Mac -> Windows: sync comparator + uia-recorder, build, print error lines only.
set -eu
cd "$(dirname "$0")/../../../.."
scripts/sync-to-win.sh probes/sr0-o/comparator 'D:\Claude\sr0o-uia\comparator' >/dev/null
scripts/sync-to-win.sh probes/sr0-o/uia-recorder 'D:\Claude\sr0o-uia\uia-recorder' >/dev/null
win "& 'D:\Claude\sr0o-uia\uia-recorder\scripts\build.ps1' *> D:\Claude\sr0o-uia\build.log; Select-String -Path D:\Claude\sr0o-uia\build.log -Pattern 'error:|swift build exit|\.exe ' | ForEach-Object { \$_.Line.Trim() } | Select -First 30" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-300
