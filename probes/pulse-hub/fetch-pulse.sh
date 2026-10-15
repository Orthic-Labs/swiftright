#!/bin/sh
# usage: fetch-pulse.sh <new empty dir> [pulse-checkout]   Exact copy of Pulse code SHA bd6bd3df (swift/ and mac/Hub only).
set -eu
SHA=bd6bd3df; OUT="$1"; REPO="${2:-/Volumes/D/claude/pulse}"
mkdir -p "$OUT"; [ -z "$(ls -A "$OUT")" ] || { echo "dir not empty" >&2; exit 2; }
git -C "$REPO" cat-file -e "$SHA" 2>/dev/null || git -C "$REPO" fetch origin
git -C "$REPO" archive "$SHA" swift mac/Hub | tar -x -C "$OUT"
