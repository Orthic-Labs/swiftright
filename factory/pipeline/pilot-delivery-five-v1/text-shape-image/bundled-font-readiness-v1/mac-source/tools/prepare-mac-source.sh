#!/bin/sh
set -eu
repo=${1:?repo}
scratch=${2:?internal scratch}
case "$scratch" in /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/*) ;; *) echo "internal scratch required" >&2; exit 2;; esac
source="$repo/factory/pipeline/pilot-delivery-five-v1/text-shape-image/bundled-font-readiness-v1/mac-source"
dest="$scratch/tinos-mac-source"
[ ! -e "$dest" ] || { echo "fresh scratch required" >&2; exit 3; }
for f in Package.swift permission-policy.json font-provisioning.json Sources/FactoryProbe/Witness.swift Sources/FactoryProbe/CaptureHost.swift Resources/Tinos-Regular.ttf; do [ -f "$source/$f" ] || { echo "missing $f" >&2; exit 4; }; done
! grep -R -E 'systemName|NSImage|Bundle\.module|CGRequestScreenCaptureAccess|AXIsProcessTrustedWithOptions' "$source/Sources" >/dev/null
mkdir -p "$dest/Sources/FactoryProbe" "$dest/Resources"
cp "$source/Package.swift" "$source/permission-policy.json" "$source/font-provisioning.json" "$dest/"
cp "$source/Sources/FactoryProbe/Witness.swift" "$source/Sources/FactoryProbe/CaptureHost.swift" "$dest/Sources/FactoryProbe/"
cp "$source/Resources/Tinos-Regular.ttf" "$dest/Resources/"
actual=$(shasum -a 256 "$dest/Resources/Tinos-Regular.ttf" | awk '{print $1}')
[ "$actual" = "60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61" ] || { echo "font hash mismatch" >&2; exit 5; }
printf '%s\n' '{"kind":"mac-tinos-source-stage-v1","probeTag":"swiftui.text.bundled-font.tinos-pilot.v1","fontHash":"sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61","compilerStarted":false,"permissionRequests":false,"status":"source-staged"}'
