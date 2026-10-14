#!/bin/sh
# Control: type-check every probe against real SwiftUI (macOS SDK). Scratch (module cache) on the internal disk.
# usage: run-mac.sh <out-log>
D=$(cd "$(dirname "$0")" && pwd); LOG=${1:-/dev/stdout}; MC=$HOME/Library/Caches/hubgap-modcache; mkdir -p "$MC"; : > "$LOG"
for t in $(cat "$D/targets.txt"); do
  if xcrun swiftc -typecheck -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 -module-cache-path "$MC" "$D/Sources/$t/Probe.swift" >"$LOG.$t" 2>&1; then echo "$t OK" >>"$LOG"; else echo "$t FAIL $(grep -m1 'error:' "$LOG.$t" | cut -c1-200)" >>"$LOG"; fi
  rm -f "$LOG.$t"
done
