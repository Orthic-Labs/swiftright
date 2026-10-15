#!/bin/zsh
# Compiles one Swift file of this folder on the INTERNAL disk (never /Volumes/D) and runs it headless (no window is ever ordered onto a screen).
# usage: mac-tool.sh NAME.swift [args...]     (the Mac capture-policy exception of factory/AGENTS.md; same pattern as symbol-metrics/symbol-sizes.sh)
set -e
here="${0:A:h}"; src="$here/$1"; shift
cache="$HOME/Library/Caches/SwiftRightFactory/image-io"; mkdir -p "$cache/mc"
bin="$cache/${src:t:r}"
/usr/bin/xcrun swiftc -parse-as-library -O -module-cache-path "$cache/mc" -o "$bin" "$src"
exec "$bin" "$@"
