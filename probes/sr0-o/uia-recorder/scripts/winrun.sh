#!/bin/sh
# Mac -> Windows: sync, build, run the interactive scheduled task. Usage: winrun.sh <record|tree> <tag>
set -eu
cd "$(dirname "$0")/../../../.."
scripts/sync-to-win.sh probes/sr0-o/uia-recorder 'D:\Claude\sr0o-uia\uia-recorder' >/dev/null
win "& 'D:\Claude\sr0o-uia\uia-recorder\scripts\build.ps1' *> D:\Claude\sr0o-uia\build.log; Select-String -Path D:\Claude\sr0o-uia\build.log -Pattern 'swift build exit' | % { \$_.Line }"
win "& 'D:\Claude\sr0o-uia\uia-recorder\scripts\schedule-record.ps1' -Mode $1 -Tag $2 $3" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
