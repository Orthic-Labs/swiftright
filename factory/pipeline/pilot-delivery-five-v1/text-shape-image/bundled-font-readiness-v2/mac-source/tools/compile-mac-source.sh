#!/bin/sh
set -eu
source=${1:?staged mac-source}
app=${2:?fresh internal app bundle}
case "$source" in /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/*) ;; *) echo "internal staged source required" >&2; exit 2;; esac
case "$app" in /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/*) ;; *) echo "internal app bundle required" >&2; exit 2;; esac
[ -f "$source/Sources/FactoryProbe/Witness.swift" ] && [ -f "$source/Sources/FactoryProbe/CaptureHost.swift" ] && [ -f "$source/Resources/Tinos-Regular.ttf" ]
[ ! -e "$app/Contents/MacOS/FactoryProbe" ] || { echo "fresh app binary required" >&2; exit 3; }
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>FactoryProbe</string><key>CFBundleIdentifier</key><string>com.swiftright.factory.tinos</string><key>CFBundleName</key><string>SwiftRightFactoryTinos</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
/usr/bin/xcrun swiftc -parse-as-library -O -o "$app/Contents/MacOS/FactoryProbe" "$source/Sources/FactoryProbe/Witness.swift" "$source/Sources/FactoryProbe/CaptureHost.swift"
chmod +x "$app/Contents/MacOS/FactoryProbe"
printf '%s\n' '{"kind":"mac-tinos-source-compile-v1","probeTag":"swiftui.text.bundled-font.tinos-pilot.v1","permissionRequests":false,"nativeActions":0,"status":"compiled"}'
