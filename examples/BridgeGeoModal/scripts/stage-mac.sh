#!/bin/sh
# Mac side: packs the sources (SwiftRightBridge package + this example) and copies them to the ONE stage dir on the Dell.
# Dell GitHub HTTPS auth is broken, so sources travel as a tar over scp (no git remote involved).
set -eu
REPO=${REPO:-/Volumes/D/claude/swiftright}
TMP=${TMPDIR:-/tmp}/geomodal-stage.$$
mkdir -p "$TMP"
COPYFILE_DISABLE=1 tar -cf "$TMP/src.tar" -C "$REPO" --exclude .build --exclude '*.o' \
  packages/SwiftRightBridge examples/BridgeGeoModal
win 'New-Item -ItemType Directory -Force D:\Claude\sr0-geomodal | Out-Null; "stage dir ready"'
scp "$TMP/src.tar" 'win:D:/Claude/sr0-geomodal/src.tar'
win 'tar -xf D:\Claude\sr0-geomodal\src.tar -C D:\Claude\sr0-geomodal; Remove-Item D:\Claude\sr0-geomodal\src.tar -Force; Get-ChildItem D:\Claude\sr0-geomodal -Directory | ForEach-Object Name'
shasum -a 256 "$REPO"/examples/BridgeGeoModal/Sources/*/main.swift "$REPO"/examples/BridgeGeoModal/scripts/* | sed "s#$REPO/##"
rm -rf "$TMP"
