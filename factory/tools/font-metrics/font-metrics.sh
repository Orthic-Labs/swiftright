#!/bin/zsh
# Builds font-metrics as a SwiftPM package on the internal disk and runs it (no screen; never builds on /Volumes/D, which prompts for TCC).
# usage: font-metrics.sh [--quick] > table.json     (the repo's Tinos is registered for the process only; throwaway lookup fonts live in a scratch dir that is moved to the Trash)
set -e
here="${0:A:h}"; repo="${here:h:h:h}"
pkg="$HOME/Library/Caches/SwiftRightFactory/font-metrics-pkg"; mkdir -p "$pkg/Sources/font-metrics"
cat > "$pkg/Package.swift" <<PKG
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "font-metrics", platforms: [.macOS(.v14)], targets: [.executableTarget(name: "font-metrics", path: "Sources/font-metrics")])
PKG
cp "$here/font-metrics.swift" "$pkg/Sources/font-metrics/main.swift"
(cd "$pkg" && swift build -c release --quiet) >&2
scratch="$HOME/Library/Caches/SwiftRightFactory/font-metrics-variants-$$"
python3 "$here/make-variants.py" "$scratch" >&2
set +e
"$pkg/.build/release/font-metrics" --fonts "$repo/factory/resources/fonts" --variants "$scratch" "$@"
rc=$?
mv "$scratch" "$HOME/.Trash/font-metrics-variants-$$" 2>/dev/null
exit $rc
