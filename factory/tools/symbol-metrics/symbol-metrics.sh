#!/bin/zsh
# Builds symbol-metrics on the internal disk and runs it (no window; never runs from /Volumes/D).
set -e
here="${0:A:h}"; cache="$HOME/Library/Caches/SwiftRightFactory/symbol-metrics"; mkdir -p "$cache/mc"
/usr/bin/xcrun swiftc -O -module-cache-path "$cache/mc" -o "$cache/symbol-metrics" "$here/symbol-metrics.swift"
exec "$cache/symbol-metrics" "$@"
