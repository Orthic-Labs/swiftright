#!/bin/zsh
# Builds symbol-metrics (module cache on /Volumes/D, binary on the internal disk; see factory/tools/cache_paths.py) and runs it (no window; never runs from /Volumes/D).
set -e
here="${0:A:h}"; cp_="$here/../cache_paths.py"; python3 "$cp_" preflight symbol-metrics
mc="$(python3 "$cp_" path build symbol-metrics)/mc"; mkdir -p "$mc"
bindir="$(python3 "$cp_" path run symbol-metrics-$$)"
/usr/bin/xcrun swiftc -O -module-cache-path "$mc" -o "$bindir/symbol-metrics" "$here/symbol-metrics.swift"
set +e; "$bindir/symbol-metrics" "$@"; rc=$?
[ $rc -eq 0 ] && python3 "$cp_" finish symbol-metrics-$$
exit $rc
