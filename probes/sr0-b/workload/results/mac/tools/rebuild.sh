#!/bin/bash
# Sync the repo workload sources into scratch, build release under --scratch-path, and wrap both executables in ad-hoc-signed .app
# bundles (same Info.plist as scripts/package-mac.sh). Nothing is run from /Volumes/D.
set -eu
W=/private/tmp/claude-501/-Volumes-D-claude-swiftright/608d5b75-d927-4ac2-a450-cee48f9d74ed/scratchpad/mac-workload
rsync -a --exclude .build --exclude .build-runtime --exclude out-mac --exclude runs --exclude results --exclude __pycache__ \
  /Volumes/D/claude/swiftright/probes/sr0-b/workload/Sources /Volumes/D/claude/swiftright/probes/sr0-b/workload/Package.swift "$W/src/"
cd "$W/src"
swift build -c release --product WorkloadMac --scratch-path "$W/build" 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" | tail -5
swift build -c release --product SckRecorder --scratch-path "$W/build" 2>&1 | grep -E "error|Build complete" | tail -3
BIN=$(swift build -c release --product WorkloadMac --scratch-path "$W/build" --show-bin-path)
OUT=$W/out-mac
mkdir -p "$OUT"
mkbundle() {
  APP="$OUT/$1.app"; mkdir -p "$APP/Contents/MacOS"; cp "$BIN/$1" "$APP/Contents/MacOS/$1"
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
  codesign --force --sign - "$APP" >/dev/null 2>&1
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
