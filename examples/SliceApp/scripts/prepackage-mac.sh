#!/bin/sh
# prePackage for the macOS target: build the executable, assemble dist/mac/SliceApp.app, Developer ID sign the app
# with its entitlements. No DMG here: right-release (>= 0.2.142) signs the app,
# notarizes and staples it, then builds, signs, notarizes and staples the DMG itself (targets.mac.dmg).
set -eu
cd "$(dirname "$0")/.."
swift build -c release
pnpm exec right-release swift-package mac-app --config swift-package.json --sign
