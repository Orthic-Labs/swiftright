#!/bin/sh
set -eu
source=${1:?staged mac-source}
app=${2:?fresh internal app bundle}
case "$source" in /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/*) ;; *) echo "internal staged source required" >&2; exit 2;; esac
case "$app" in /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/*) ;; *) echo "internal app bundle required" >&2; exit 2;; esac
[ -d "$source/Resources/FactoryRGBA.xcassets" ]
mkdir -p "$app/Contents/Resources" "$app/Contents/MacOS"
[ ! -e "$app/Contents/Resources/Assets.car" ] || { echo "fresh app assets required" >&2; exit 3; }
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>FactoryProbe</string><key>CFBundleIdentifier</key><string>com.swiftright.factory.image</string><key>CFBundleName</key><string>SwiftRightFactoryImage</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
/usr/bin/xcrun actool --compile "$app/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 "$source/Resources/FactoryRGBA.xcassets"
[ -f "$app/Contents/Resources/Assets.car" ]
printf '%s\n' '{"kind":"mac-main-bundle-assets-v2","probeTag":"swiftui.image.rgba-registered.v1","bundleLookup":"Bundle.main","assetCompiler":"/usr/bin/xcrun actool","permissionRequests":false}'
