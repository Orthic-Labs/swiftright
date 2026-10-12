#!/bin/sh
set -eu
SOURCE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CACHE_ROOT=${SWIFTRIGHT_MAC_CACHE_ROOT:-/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-matched-scale-v1}
case "$CACHE_ROOT" in /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-matched-scale-v1) ;; *) echo 'exact internal Mac cache root required' >&2; exit 64 ;; esac
case "$SOURCE_ROOT" in /Volumes/D/*) ;; *) echo 'source checkout identity unexpected' >&2; exit 64 ;; esac
[ ! -e "$CACHE_ROOT" ] || { echo 'fresh Mac cache root required' >&2; exit 73; }
STAGED="$CACHE_ROOT/source"
SCRATCH="$CACHE_ROOT/scratch"
BUILD="$CACHE_ROOT/build"
BIN="$CACHE_ROOT/bin"
mkdir -p "$STAGED" "$SCRATCH" "$BUILD" "$BIN"
cp "$SOURCE_ROOT/Package.swift" "$STAGED/Package.swift"
cp -R "$SOURCE_ROOT/Sources" "$STAGED/Sources"
if grep -R -n '/Volumes/D/\|factory-swiftright\|sr0-r09' "$STAGED/Sources" >/dev/null 2>&1; then
  echo 'staged Mac source contains forbidden checkout path' >&2
  exit 65
fi
SOURCE_HASH=$(shasum -a 256 "$STAGED/Sources/CustomLayoutMacHost/Witness.swift" | awk '{print $1}')
cat > "$CACHE_ROOT/source-join.json" <<EOF
{"kind":"factory-custom-layout-matched-scale-mac-staged-source-v1","sourceRoot":"$STAGED","scratchRoot":"$SCRATCH","buildRoot":"$BUILD","binRoot":"$BIN","rootSupervisor":"/Volumes/D/claude/swiftright/factory/tools/supervise-job-v2.py","maxResidentBytes":1073741824,"witnessHash":"sha256:$SOURCE_HASH","nativeActions":0}
EOF
cat <<EOF
SOURCE_ROOT=$STAGED
SCRATCH_ROOT=$SCRATCH
BUILD_ROOT=$BUILD
BIN_ROOT=$BIN
ROOT_GROUP_SUPERVISOR=/Volumes/D/claude/swiftright/factory/tools/supervise-job-v2.py
WITNESS_HASH=sha256:$SOURCE_HASH
EOF
