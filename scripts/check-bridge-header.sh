#!/bin/sh
# The bridge package carries a regular-file copy of the ABI header (RightKit ownership preflight rejects
# committed symlinks). The single source of truth stays render/swiftright-abi/include/swiftright.h.
# Usage: scripts/check-bridge-header.sh [--fix]
cd "$(dirname "$0")/.." || exit 2
src=render/swiftright-abi/include/swiftright.h
dst=packages/SwiftRightBridge/Sources/CSwiftRight/swiftright.h
if cmp -s "$src" "$dst"; then echo "bridge header in sync"; exit 0; fi
if [ "$1" = "--fix" ]; then cp "$src" "$dst" && echo "bridge header updated from $src"; exit 0; fi
echo "bridge header differs from $src; run scripts/check-bridge-header.sh --fix" >&2; exit 1
