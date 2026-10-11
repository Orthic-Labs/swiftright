#!/bin/sh
# Tuple12 Windows fixture matrix launcher; never invoked by preparation.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${BASE_DIR:?set BASE_DIR to tuple12 Dell source tree}"
: "${EXPECT_EXE_SHA256:?set tuple12 FreshOnBridge.exe hash}"
: "${EXPECT_DLL_SHA256:?set tuple12 renderer hash}"
: "${OUT_DIR:?set unique tuple12 matrix output directory}"
case "$EXPECT_EXE_SHA256$EXPECT_DLL_SHA256" in *[!0-9A-Fa-f]*) exit 2;; esac
[ "${#EXPECT_EXE_SHA256}" -eq 64 ] && [ "${#EXPECT_DLL_SHA256}" -eq 64 ] || exit 2
export BASE_DIR EXPECT_EXE_SHA256 EXPECT_DLL_SHA256 OUT_DIR
export RUNS=${RUNS:-20}
exec sh "$ROOT/probes/sr0-s/fresh-on-bridge/scripts/run-matrix.sh" "$@"
