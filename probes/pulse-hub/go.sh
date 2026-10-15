#!/bin/sh
# usage: go.sh <work dir name> <tag> <local logs dir> : push shim, run iter.ps1 on the Dell, fetch the logs, print new error summary
set -eu; H="$(cd "$(dirname "$0")" && pwd)"; N="$1"; T="$2"; L="$3"; D="D:/Claude/swiftright/.work/$N"
"$H/push.sh" "$N"
ssh win "Set-Location D:\\Claude; & $D/iter.ps1 -Work $D -Tag $T ${4:+-Swift $4 -ModsDir mods$4}"
mkdir -p "$L"
for m in SwiftUI RightKitHub RightKitHubQA PulseHub PulseHubFixtures; do scp -q "win:$D/$T-$m.log" "$L/" 2>/dev/null || true; done
