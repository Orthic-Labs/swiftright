#!/bin/zsh
# Compiles one Swift file of this folder (module cache on /Volumes/D, binary on the internal disk; see factory/tools/cache_paths.py) and runs it headless (no window is ever ordered onto a screen).
# usage: mac-tool.sh NAME.swift [args...]     (the Mac capture-policy exception of factory/AGENTS.md; same pattern as symbol-metrics/symbol-sizes.sh)
set -e
here="${0:A:h}"; src="$here/$1"; shift
cp_="$here/../cache_paths.py"; python3 "$cp_" preflight image-io
mc="$(python3 "$cp_" path build image-io)/mc"; mkdir -p "$mc"            # module cache on /Volumes/D (compile only)
bindir="$(python3 "$cp_" path run image-io-$$)"; bin="$bindir/${src:t:r}"   # the binary launched lives on the internal disk, capped
/usr/bin/xcrun swiftc -parse-as-library -O -module-cache-path "$mc" -o "$bin" "$src"
set +e; "$bin" "$@"; rc=$?
[ $rc -eq 0 ] && python3 "$cp_" finish image-io-$$
exit $rc
