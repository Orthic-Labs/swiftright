#!/bin/sh
# usage: push.sh <work dir name under .work> : copies probe scripts and shim sources to the Dell work dir (no deletes)
set -eu; H="$(cd "$(dirname "$0")" && pwd)"; D="D:/Claude/swiftright/.work/$1"
scp -q "$H/tc.ps1" "$H/iter.ps1" "$H/run.ps1" win:$D/
scp -q "$H"/shim/*.swift win:$D/pkg/Sources/SwiftUI/
ssh win "New-Item -ItemType Directory -Force $D/pkg/Sources/FactoryProbe | Out-Null"
scp -q "$H"/host/*.swift win:$D/pkg/Sources/FactoryProbe/
# Package.swift with the stage placeholder set to the patched stage inside the work dir
WD="D:/Claude/swiftright/.work/$1/stage-patched"
sed "s#@@PRODUCT_STAGE@@#$WD#" "$H/Package.swift" > /tmp/pulse-hub-Package.swift
scp -q /tmp/pulse-hub-Package.swift win:$D/pkg/Package.swift
