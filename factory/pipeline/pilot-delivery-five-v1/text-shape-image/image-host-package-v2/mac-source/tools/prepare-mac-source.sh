#!/bin/sh
set -eu
repo=${1:?repo}
scratch=${2:?internal scratch}
case "$repo" in /Volumes/D/*) echo "source checkout may be read only" >&2;; esac
case "$scratch" in /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/*) ;; *) echo "internal scratch required" >&2; exit 2;; esac
source="$repo/factory/pipeline/pilot-delivery-five-v1/text-shape-image/image-host-package-v2/mac-source"
dest="$scratch/image-mac-source"
[ ! -e "$dest" ] || { echo "fresh scratch required" >&2; exit 3; }
[ -f "$source/Sources/FactoryProbe/Witness.swift" ]
[ -f "$source/Sources/FactoryProbe/CaptureHost.swift" ]
[ -d "$source/Resources/FactoryRGBA.xcassets" ]
! grep -R -E 'systemName|NSImage|Bundle\.module|CGRequestScreenCaptureAccess|AXIsProcessTrustedWithOptions' "$source/Sources" >/dev/null
mkdir -p "$dest"
cp -R "$source/." "$dest/"
printf '%s\n' '{"kind":"mac-source-stage-v2","probeTag":"swiftui.image.rgba-registered.v1","compilerStarted":false,"permissionRequests":false,"status":"source-staged"}'
