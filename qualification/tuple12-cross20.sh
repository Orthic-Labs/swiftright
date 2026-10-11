#!/bin/sh
# Tuple12 Windows cross-recording launcher; caller supplies lock-safe output path & pins.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${BIN:?set BIN to tuple12 Dell release directory}"
: "${EXPECT_EXE:?set tuple12 FreshOnBridge.exe hash}"
: "${EXPECT_RENDERER:?set tuple12 renderer hash}"
OUT=${1:?usage: tuple12-cross20.sh OUT_DIR [CONFIG ...]}
shift
if [ "$#" -eq 0 ]; then
    set -- F1 F2 F3 F3-list-1s F3-list-3s F3-vstack-1s F3-vstack-3s F3-lazy-1s F3-lazy-3s F4 F5 F6 F6-reduced F7 F8 F9
fi
export BIN EXPECT_EXE EXPECT_RENDERER FIRST=${FIRST:-1} TAGP=${TAGP:-t12}
exec sh "$ROOT/probes/sr0-o/f1-cross/scripts/win-cross.sh" "$OUT" 20 "$@"
