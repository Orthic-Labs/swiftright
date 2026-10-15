#!/bin/sh
# usage: [PULSE_SHA=<sha>] fetch-pulse.sh <new empty dir> [pulse-checkout]   Exact copy of Pulse code at PULSE_SHA (default bd6bd3df; round 5: f8460ed5) (swift/ and mac/Hub only).
set -eu
SHA="${PULSE_SHA:-bd6bd3df}"; OUT="$1"; REPO="${2:-/Volumes/D/claude/pulse}"
mkdir -p "$OUT"; [ -z "$(ls -A "$OUT")" ] || { echo "dir not empty" >&2; exit 2; }
git -C "$REPO" cat-file -e "$SHA" 2>/dev/null || git -C "$REPO" fetch origin
git -C "$REPO" archive "$SHA" swift mac/Hub | tar -x -C "$OUT"
