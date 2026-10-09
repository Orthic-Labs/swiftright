#!/bin/sh
# prePackage for the macOS target: build the executable and assemble dist/mac/SliceApp.app (unsigned).
# Signing, notarization and archiving are right-release's steps, run after this script.
set -eu
cd "$(dirname "$0")/.."
swift build -c release
pnpm exec right-release swift-package mac-app --config swift-package.json
