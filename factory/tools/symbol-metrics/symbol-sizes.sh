#!/bin/zsh
# Builds symbol-sizes as a SwiftPM package on the internal disk and runs it (no window; never builds on /Volumes/D).
set -e
here="${0:A:h}"; pkg="$HOME/Library/Caches/SwiftRightFactory/symbol-sizes-pkg"; mkdir -p "$pkg/Sources/symbol-sizes"
cat > "$pkg/Package.swift" <<PKG
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "symbol-sizes", platforms: [.macOS(.v14)], targets: [.executableTarget(name: "symbol-sizes", path: "Sources/symbol-sizes")])
PKG
cp "$here/symbol-sizes.swift" "$pkg/Sources/symbol-sizes/main.swift"
(cd "$pkg" && swift build -c release --quiet)
exec "$pkg/.build/release/symbol-sizes" "$@"
