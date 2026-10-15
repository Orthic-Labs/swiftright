#!/bin/zsh
# Builds symbol-sizes as a SwiftPM package (on /Volumes/D, compile only) and runs an internal copy of the binary (no window; see factory/tools/cache_paths.py).
set -e
here="${0:A:h}"; cp_="$here/../cache_paths.py"; python3 "$cp_" preflight symbol-sizes
pkg="$(python3 "$cp_" path build symbol-sizes)/pkg"; mkdir -p "$pkg/Sources/symbol-sizes"   # sources + SwiftPM scratch on /Volumes/D (compile only)
scratch="$(python3 "$cp_" path build symbol-sizes)/scratch"; lane="symbol-sizes-$$"; bindir="$(python3 "$cp_" path run $lane)"
cat > "$pkg/Package.swift" <<PKG
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "symbol-sizes", platforms: [.macOS(.v14)], targets: [.executableTarget(name: "symbol-sizes", path: "Sources/symbol-sizes")])
PKG
cp "$here/symbol-sizes.swift" "$pkg/Sources/symbol-sizes/main.swift"
swift build --package-path "$pkg" --scratch-path "$scratch" -c release --quiet
cp "$(swift build --package-path "$pkg" --scratch-path "$scratch" -c release --show-bin-path)/symbol-sizes" "$bindir/symbol-sizes"   # launch the internal copy
set +e; "$bindir/symbol-sizes" "$@"; rc=$?
[ $rc -eq 0 ] && python3 "$cp_" finish $lane
exit $rc
