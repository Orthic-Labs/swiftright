#!/bin/sh
# Builds the macOS workload in release and wraps both executables in minimal .app bundles (stable identity for the
# TCC grants the recorder needs; Developer ID signed with the same identity as F1MacRecord). Build only: nothing is launched.
# Installs each bundle at ONE fixed path under $HOME/Applications/SwiftRight/ (in place; previous copy kept as
# <name>.previous.app). Adrian's rule 2026-10-17: no new id, no new folder. $OUT is build scratch only.
# Usage: scripts/package-mac.sh [out-dir]   (default: probes/sr0-b/workload/out-mac)
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/../../../qualification/install-in-place.sh"
OUT=${1:-$HERE/out-mac}
cd "$HERE"
swift build -c release --product WorkloadMac
swift build -c release --product SckRecorder
BIN=$(swift build -c release --show-bin-path)
rm -rf "$OUT"; mkdir -p "$OUT"
mkbundle() { # name bundle-id uielement
  APP="$OUT/$1.app"; mkdir -p "$APP/Contents/MacOS"
  cp "$BIN/$1" "$APP/Contents/MacOS/$1"
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$1</string>
<key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundleName</key><string>$1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><$3/>
</dict></plist>
PLIST
  codesign --force --sign "$SR_SIGN_IDENTITY" --identifier "$2" "$APP" >/dev/null
}
mkbundle WorkloadMac com.orthiclabs.sr0.workload false
mkbundle SckRecorder com.orthiclabs.sr0.sckrecorder true
{
  echo "{"
  echo "  \"built_utc\": \"$(date -u +%FT%TZ)\","
  echo "  \"swift\": \"$(swift --version 2>&1 | head -1 | sed 's/"/\\"/g')\","
  echo "  \"configuration\": \"release\","
  echo "  \"workload_sha256\": \"$(shasum -a 256 "$OUT/WorkloadMac.app/Contents/MacOS/WorkloadMac" | cut -d' ' -f1)\","
  echo "  \"recorder_sha256\": \"$(shasum -a 256 "$OUT/SckRecorder.app/Contents/MacOS/SckRecorder" | cut -d' ' -f1)\""
  echo "}"
} > "$OUT/build-mac.json"
cat "$OUT/build-mac.json"
echo "bundles built in scratch $OUT"
# Hash the built executables above, then move each signed bundle to its fixed path.
install_in_place "$OUT/WorkloadMac.app" WorkloadMac com.orthiclabs.sr0.workload
install_in_place "$OUT/SckRecorder.app" SckRecorder com.orthiclabs.sr0.sckrecorder
# run-mac.sh and run_one.sh read build-mac.json from the fixed dir; keep the scratch copy too.
cp "$OUT/build-mac.json" "$SR_APP_DIR/build-mac.json"
