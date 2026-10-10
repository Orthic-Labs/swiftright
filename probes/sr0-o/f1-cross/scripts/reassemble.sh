#!/bin/sh
# Rebuilds every schema-v0 trace of the cross-compare from the committed RAW recordings and in-process events, offline
# (no Mac GUI, no Dell). Raw = the recorders' own output, kept gzipped in cross-evidence/<config>/raw/:
#   mac-raw-n<i>.json.gz (F1MacRecord), win-rec-w<i>.json.gz + win-side-w<i>.json.gz (UIARecorder);
# events = cross-evidence/<config>/mac-ev-n<i>.jsonl and win-events-w<i>.txt (the fixtures' in-process instrumentation).
# Writes cross-evidence/<config>/{mac-trace-n<i>,win-trace-w<i>}.json and the compare inputs
# cross/<config>/{mac-trace-v0,win-trace-v0}.json (run 1; F1 keeps its promoted Mac baseline, no cross/F1/mac-trace-v0.json).
# Usage: reassemble.sh <F1Assemble binary> [config...]      (binary built under a scratch root, never from /Volumes/D)
set -eu
ASM=$1; shift
HERE=$(cd "$(dirname "$0")/.." && pwd)
if [ "$#" -eq 0 ]; then set -- F1 F2 F3 F3-list-1s F3-list-3s F3-vstack-1s F3-vstack-3s F3-lazy-1s F3-lazy-3s F4 F5 F6 F6-reduced F7 F8 F9; fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/reassemble.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
for c in "$@"; do
  ev="$HERE/cross-evidence/$c"; stim="$HERE/cross/$c/stimulus.json"
  for i in 1 2 3; do
    gunzip -c "$ev/raw/mac-raw-n$i.json.gz" > "$TMP/mac-raw.json"
    "$ASM" mac --raw "$TMP/mac-raw.json" --events "$ev/mac-ev-n$i.jsonl" --stimulus "$stim" --out "$ev/mac-trace-n$i.json" --keep-lists >/dev/null
    gunzip -c "$ev/raw/win-rec-w$i.json.gz" > "$TMP/win-rec.json"
    gunzip -c "$ev/raw/win-side-w$i.json.gz" > "$TMP/win-side.json"
    "$ASM" win --rec "$TMP/win-rec.json" --side "$TMP/win-side.json" --events "$ev/win-events-w$i.txt" --stimulus "$stim" --out "$ev/win-trace-w$i.json" --keep-lists >/dev/null
    rm -f "$ev/mac-trace-n$i.json.notes.json" "$ev/win-trace-w$i.json.notes.json"
  done
  [ "$c" = F1 ] || cp "$ev/mac-trace-n1.json" "$HERE/cross/$c/mac-trace-v0.json"
  cp "$ev/win-trace-w1.json" "$HERE/cross/$c/win-trace-v0.json"
  echo "$c reassembled"
done
