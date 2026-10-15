#!/bin/sh
# usage: cycle2.sh <work dir> <tag> <start frame> <frames> <out dir> : build host, deploy, set the guest counter, ONE interact job
set -eu; H="$(cd "$(dirname "$0")" && pwd)"; N="$1"; T="$2"
"$H/push.sh" "$N"
ssh win "Set-Location D:\\Claude; & D:\\Claude\\swiftright\\.work\\$N\\buildhost.ps1 -Work D:\\Claude\\swiftright\\.work\\$N -Tag $T; Select-String -Path D:\\Claude\\swiftright\\.work\\$N\\$T.log -Pattern ': error:' | % Line"
"$H/deploy.sh" "$N" release
"$H/setframe.sh" "$3" "$5-sf" >/dev/null
python3 "$H/render.py" 'D:\Claude\swiftright\.factory-work\hosts\pulse-hub-20261015\package\scratch\x86_64-unknown-windows-msvc\release\FactoryProbe.exe' "$4" "$5" | sed -n 1,4p
