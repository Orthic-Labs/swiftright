#!/bin/sh
set -eu
repo=${1:?repo}
scratch=${2:?internal scratch}
case "$repo" in /Volumes/D/*) echo "source checkout may be read only" >&2;; esac
case "$scratch" in /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/rounded-stroke-matched-scale-v1/*) ;; *) echo "internal scratch required" >&2; exit 2;; esac
source="$repo/factory/pipeline/pilot-delivery-five-v1/stack-layout/rounded-stroke-matched-scale-v1/mac-source"
dest="$scratch/rounded-stroke-mac-source"
[ ! -e "$dest" ] || { echo "fresh scratch required" >&2; exit 3; }
[ -f "$source/Sources/FactoryProbe/Witness.swift" ]
[ -f "$source/Sources/FactoryProbe/CaptureHost.swift" ]
! grep -R -E 'systemName|NSImage|Bundle\.module|CGRequestScreenCaptureAccess|AXIsProcessTrustedWithOptions' "$source/Sources" >/dev/null
mkdir -p "$dest"
cp -R "$source/." "$dest/"
printf '%s\n' '{"kind":"mac-source-stage-v1","probeTag":"swiftui.shapes.fill-stroke.abi-rect-border.v1","compilerStarted":false,"permissionRequests":false,"status":"source-staged"}'
