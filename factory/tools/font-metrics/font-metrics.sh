#!/bin/zsh
# Builds font-metrics as a SwiftPM package (compile on /Volumes/D, run an internal copy of the binary: only launching from /Volumes/D prompts for TCC; see factory/tools/cache_paths.py) and runs it (no screen).
# usage: font-metrics.sh [--quick] > table.json     (the repo's Tinos is registered for the process only; throwaway lookup fonts live in a scratch dir that is moved to the Trash)
set -e
here="${0:A:h}"; repo="${here:h:h:h}"
cp_="$here/../cache_paths.py"; python3 "$cp_" preflight font-metrics
pkg="$(python3 "$cp_" path build font-metrics)/pkg"; mkdir -p "$pkg/Sources/font-metrics"   # sources + SwiftPM scratch on /Volumes/D (compile only)
sc="$(python3 "$cp_" path build font-metrics)/scratch"; lane="font-metrics-$$"; bindir="$(python3 "$cp_" path run $lane)"
cat > "$pkg/Package.swift" <<PKG
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "font-metrics", platforms: [.macOS(.v14)], targets: [.executableTarget(name: "font-metrics", path: "Sources/font-metrics")])
PKG
cp "$here/font-metrics.swift" "$pkg/Sources/font-metrics/main.swift"
swift build --package-path "$pkg" --scratch-path "$sc" -c release --quiet >&2
cp "$(swift build --package-path "$pkg" --scratch-path "$sc" -c release --show-bin-path)/font-metrics" "$bindir/font-metrics"   # launch the internal copy
scratch="$bindir/variants"
python3 "$here/make-variants.py" "$scratch" >&2
set +e
"$bindir/font-metrics" --fonts "$repo/factory/resources/fonts" --variants "$scratch" "$@"
rc=$?
[ $rc -eq 0 ] && python3 "$cp_" finish $lane     # moves the run lane (incl. variants) out of the internal disk
exit $rc
