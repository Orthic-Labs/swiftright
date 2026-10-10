#!/bin/sh
# Records the Mac schema-v0 cross trace for each config. Never runs a binary from /Volumes/D: the signed recorder and the
# FixtureApp must be under the scratch root. Usage:
#   record-mac.sh <recorder-binary> <FixtureApp> <F1Assemble> <out-dir> <tag> <config>...
set -u
REC=$1; FA=$2; ASM=$3; OUT=$4; TAG=$5; shift 5
HERE=$(cd "$(dirname "$0")/.." && pwd)
for c in "$@"; do
  d="$OUT/$c"; mkdir -p "$d"
  "$REC" --fixture "$FA" --events "$d/mac-ev-$TAG.jsonl" --out "$d/mac-raw-$TAG.json" --steps "$HERE/cross/$c/steps-mac.json" >"$d/mac-rec-$TAG.log" 2>&1
  rc=$?
  "$ASM" mac --raw "$d/mac-raw-$TAG.json" --events "$d/mac-ev-$TAG.jsonl" --stimulus "$HERE/cross/$c/stimulus.json" --out "$d/mac-trace-$TAG.json" --keep-lists >>"$d/mac-rec-$TAG.log" 2>&1
  echo "$c rec_rc=$rc asm_rc=$? $(tail -1 "$d/mac-rec-$TAG.log" | cut -c1-200)"
done
