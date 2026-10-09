#!/bin/sh
# package step for the macOS target: rebuild the branded DMG from the signed, notarized and stapled
# dist/mac/SliceApp.app (right-release runs this after notarize.appBeforePackage), replacing the first DMG that
# prepackage-mac.sh made. postSign signs the DMG container; right-release then notarizes and staples the DMG.
set -eu
cd "$(dirname "$0")/.."
pnpm exec right-release dmg build \
  --app dist/mac/SliceApp.app \
  --out dist/mac/SliceApp_0.1.0_arm64.dmg \
  --volname SliceApp \
  --background Mac/dmg/background.tiff \
  --window 660,400 \
  --icon-size 128 \
  --app-position 158,231 \
  --applications-position 492,231
