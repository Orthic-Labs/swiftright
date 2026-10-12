#!/bin/sh
set -eu
CACHE_ROOT=/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-rtl-width32-v5
PACKAGE="$CACHE_ROOT/source"
SCRATCH="$CACHE_ROOT/scratch"
BUILD="$CACHE_ROOT/build"
BIN="$CACHE_ROOT/bin"
[ -f "$PACKAGE/Package.swift" ] || { echo 'staged Mac source missing; run prepare-mac-source.sh' >&2; exit 66; }
case "$PACKAGE" in /Volumes/D/*) echo 'build package must be internal staged source' >&2; exit 65 ;; esac
mkdir -p "$BUILD" "$BIN"
SUPERVISOR=/Volumes/D/claude/swiftright/factory/tools/supervise-job-v2.py
[ -f "$SUPERVISOR" ] || { echo 'root group supervisor source missing' >&2; exit 64; }
REQUEST="$CACHE_ROOT/compile-request.json"
cat > "$REQUEST" <<EOF
{
  "kind": "factory-custom-layout-mac-root-supervised-compile-request-v1",
  "packagePath": "$PACKAGE",
  "scratchPath": "$BUILD",
  "binaryRoot": "$BIN",
  "supervisorScript": "$SUPERVISOR",
  "supervisorArgs": ["--seconds", "600", "--rss-mib", "1024", "--log-mib", "128", "--out", "$CACHE_ROOT/supervisor-receipt", "--"],
  "swiftBuildArgs": ["swift", "build", "--package-path", "$PACKAGE", "--scratch-path", "$BUILD", "--jobs", "1", "-c", "release"],
  "frontendThreadFlagCandidates": [["-Xswiftc", "-Xfrontend", "-Xswiftc", "-num-threads", "-Xswiftc", "-Xfrontend", "-Xswiftc", "1"]],
  "maxResidentBytes": 1073741824,
  "nativeActions": 0,
  "binaryHashClaims": 0
}
EOF
cat "$REQUEST"
