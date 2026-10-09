#!/bin/sh
# prePackage for the macOS target: build the executable, assemble dist/mac/SliceApp.app, Developer ID sign the app
# with its entitlements, then build the branded DMG from the signed app (dist/mac/SliceApp_0.1.0_arm64.dmg).
# The DMG container is signed, notarized and stapled by right-release after this script (release.mjs mac branch).
set -eu
cd "$(dirname "$0")/.."
swift build -c release
pnpm exec right-release swift-package mac-app --config swift-package.json --sign
pnpm exec right-release dmg build \
  --app dist/mac/SliceApp.app \
  --out dist/mac/SliceApp_0.1.0_arm64.dmg \
  --volname SliceApp \
  --background Mac/dmg/background.tiff \
  --window 660,400 \
  --icon-size 128 \
  --app-position 158,231 \
  --applications-position 492,231
