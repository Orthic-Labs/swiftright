#!/bin/sh
# Mac side: packs the sources (SwiftRightBridge package + this example) and copies them to the ONE stage dir on the Dell.
# Dell GitHub HTTPS auth is broken, so sources travel as a tar over scp (no git remote involved).
set -eu
REPO=${REPO:-/Volumes/D/claude/swiftright}
# STAGE (Windows path, default the rows 6-7 stage dir); the modal-stall fix uses STAGE='D:\Claude\sr0-modalfix'.
STAGE=${STAGE:-'D:\Claude\sr0-geomodal'}
STAGE_SCP=$(printf '%s' "$STAGE" | tr '\\' '/')
TMP=${TMPDIR:-/tmp}/geomodal-stage.$$
mkdir -p "$TMP"
COPYFILE_DISABLE=1 tar -cf "$TMP/src.tar" -C "$REPO" --exclude .build --exclude '*.o' \
  packages/SwiftRightBridge examples/BridgeGeoModal
win "New-Item -ItemType Directory -Force '$STAGE' | Out-Null; 'stage dir ready'"
scp "$TMP/src.tar" "win:$STAGE_SCP/src.tar"
win "tar -xf '$STAGE\src.tar' -C '$STAGE'; Remove-Item '$STAGE\src.tar' -Force; Get-ChildItem '$STAGE' -Directory | ForEach-Object Name"
shasum -a 256 "$REPO"/examples/BridgeGeoModal/Sources/*/main.swift "$REPO"/examples/BridgeGeoModal/scripts/* | sed "s#$REPO/##"
rm -rf "$TMP"
