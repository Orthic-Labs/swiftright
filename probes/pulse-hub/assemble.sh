#!/bin/sh
# usage: [R5=1] assemble.sh <pulse-src dir (from fetch-pulse.sh)> <new empty dest dir>
# R5=1 (round 5, the unpatched re-probe): the shim is only the SwiftUI re-export (no compile stubs: Stubs.swift is not copied) and Pulse sources are untouched (no bypass B1).
# Builds the probe package tree: Pulse's sources copied unmodified into one target per module, plus the shim and link stubs.
set -eu
SRC="$1"; DEST="$2"; HERE="$(cd "$(dirname "$0")" && pwd)"
[ -z "$(ls -A "$DEST" 2>/dev/null)" ] || { echo "dest not empty" >&2; exit 2; }
S="$DEST/Sources"; mkdir -p "$S"
cp "$HERE/Package.swift" "$DEST/"
if [ "${R5:-0}" = 1 ]; then mkdir -p "$S/SwiftUI"; cp "$HERE/shim/SwiftUIShim.swift" "$S/SwiftUI/"; else cp -R "$HERE/shim" "$S/SwiftUI"; fi
K="$SRC/swift/RightKitHub/Sources"
for m in RightKitEngine RightKitHub RightKitHubQA CRightKitEngine; do cp -R "$K/$m" "$S/$m"; done
rm "$S/CRightKitEngine/shim.c"; cp "$HERE/stubs/rkp_stubs.c" "$S/CRightKitEngine/"
for m in PulseHub PulseHubFixtures; do cp -R "$SRC/mac/Hub/Sources/$m" "$S/$m"; done
mkdir -p "$S/FactoryProbe"; cp "$HERE"/host/*.swift "$S/FactoryProbe/"
if [ "${R5:-0}" != 1 ]; then python3 "$HERE/bypass.py" "$DEST"; fi
