#!/bin/sh
set -eu

# Build generalized F1MacRecord from a commit-pinned source archive in a
# fresh internal scratch namespace. This script never signs, deletes, or
# reuses output. Signing remains held pending process-level no-prompt proof.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
SOURCE_COMMIT=0e201571e4320a3b6ccce14313fd2ad67e523904
PACKAGE_PATH=probes/sr0-o/f1-cross
SOURCE_PATH=$PACKAGE_PATH/Sources/F1MacRecord/main.swift
PACKAGE_SHA=3a30e1894d6379c2ed5c0cbb60fdeb7046fb29eab915eacea78054118622f92a
SOURCE_SHA=90de6c1bca7fd114afc754ff2491e8732f9bd8b3922dce76d7aa9e34c7201507
OUT=${1:?usage: prepare-mac-recorder.sh <fresh-internal-output>}

case "$OUT" in
  "$HOME"/*) ;;
  *) echo "output must be under HOME on internal disk: $OUT" >&2; exit 2 ;;
esac
[ ! -e "$OUT" ] || { echo "output exists; choose fresh namespace: $OUT" >&2; exit 2; }

command -v git >/dev/null 2>&1 || { echo "git unavailable" >&2; exit 2; }
command -v shasum >/dev/null 2>&1 || { echo "shasum unavailable" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 unavailable" >&2; exit 2; }
command -v tar >/dev/null 2>&1 || { echo "tar unavailable" >&2; exit 2; }
command -v xcrun >/dev/null 2>&1 || { echo "xcrun unavailable" >&2; exit 2; }

# Validate commit-bound bytes before creating output. rev-parse is deliberately
# not used for content hashes: Git object IDs may be SHA-1 while receipts use
# SHA-256 bytes.
git -C "$ROOT" cat-file -e "$SOURCE_COMMIT^{commit}" || {
  echo "source commit unavailable: $SOURCE_COMMIT" >&2; exit 2;
}
commit_source_sha=$(git -C "$ROOT" show "$SOURCE_COMMIT:$SOURCE_PATH" | shasum -a 256 | awk '{print $1}')
commit_package_sha=$(git -C "$ROOT" show "$SOURCE_COMMIT:$PACKAGE_PATH/Package.swift" | shasum -a 256 | awk '{print $1}')
[ "$commit_source_sha" = "$SOURCE_SHA" ] || { echo "pinned source SHA mismatch: $commit_source_sha" >&2; exit 2; }
[ "$commit_package_sha" = "$PACKAGE_SHA" ] || { echo "pinned Package.swift SHA mismatch: $commit_package_sha" >&2; exit 2; }

# Atomic creation closes check-then-create race & keeps fresh namespace rule.
mkdir "$OUT"
ARCHIVE="$OUT/source-archive.tar"
git -C "$ROOT" archive --format=tar --output="$ARCHIVE" "$SOURCE_COMMIT" "$PACKAGE_PATH"
SOURCE_ROOT="$OUT/source"
mkdir "$SOURCE_ROOT"
tar -xf "$ARCHIVE" -C "$SOURCE_ROOT"
PKG="$SOURCE_ROOT/$PACKAGE_PATH"
SRC="$PKG/Sources/F1MacRecord/main.swift"
[ -f "$SRC" ] || { echo "archived source missing: $SRC" >&2; exit 2; }
[ -f "$PKG/Package.swift" ] || { echo "archived Package.swift missing: $PKG/Package.swift" >&2; exit 2; }
if find "$PKG" -type l -print -quit | grep -q .; then
  echo "archived package contains symlink" >&2
  exit 2
fi
actual_source_sha=$(shasum -a 256 "$SRC" | awk '{print $1}')
actual_package_sha=$(shasum -a 256 "$PKG/Package.swift" | awk '{print $1}')
[ "$actual_source_sha" = "$SOURCE_SHA" ] || { echo "archived source SHA mismatch: $actual_source_sha" >&2; exit 2; }
[ "$actual_package_sha" = "$PACKAGE_SHA" ] || { echo "archived Package.swift SHA mismatch: $actual_package_sha" >&2; exit 2; }

XCRUN_PATH=$(command -v xcrun)
SWIFT_PATH=$(xcrun --find swift)
SWIFTC_PATH=$(xcrun --find swiftc)
XCRUN_REAL=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$XCRUN_PATH")
SWIFT_REAL=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SWIFT_PATH")
SWIFTC_REAL=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SWIFTC_PATH")
xcrun --version >"$OUT/xcrun-version.txt" 2>"$OUT/xcrun-version.stderr"
"$SWIFT_PATH" --version >"$OUT/swift-version.txt" 2>"$OUT/swift-version.stderr"
"$SWIFTC_PATH" --version >"$OUT/swiftc-version.txt" 2>"$OUT/swiftc-version.stderr"

SCRATCH="$OUT/swiftpm"
BUILD_STDOUT="$OUT/swift-build.stdout"
BUILD_STDERR="$OUT/swift-build.stderr"
set +e
xcrun swift build -c release --package-path "$PKG" --scratch-path "$SCRATCH" --product F1MacRecord >"$BUILD_STDOUT" 2>"$BUILD_STDERR"
build_rc=$?
set -e
[ "$build_rc" -eq 0 ] || { echo "swift build failed: exit $build_rc (see $BUILD_STDERR)" >&2; exit 2; }

# Resolve bin path only after successful build; --show-bin-path itself does
# not compile anything.
BINPATH_STDOUT="$OUT/show-bin-path.stdout"
BINPATH_STDERR="$OUT/show-bin-path.stderr"
set +e
xcrun swift build -c release --package-path "$PKG" --scratch-path "$SCRATCH" --product F1MacRecord --show-bin-path >"$BINPATH_STDOUT" 2>"$BINPATH_STDERR"
binpath_rc=$?
set -e
[ "$binpath_rc" -eq 0 ] || { echo "swift --show-bin-path failed: exit $binpath_rc" >&2; exit 2; }
BIN_DIR=$(awk 'NF { print; exit }' "$BINPATH_STDOUT")
[ -n "$BIN_DIR" ] || { echo "swift --show-bin-path returned empty path" >&2; exit 2; }
case "$BIN_DIR" in "$SCRATCH"/*) ;; *) echo "bin path escaped fresh scratch: $BIN_DIR" >&2; exit 2 ;; esac
BIN="$BIN_DIR/F1MacRecord"
[ -f "$BIN" ] || { echo "built recorder missing: $BIN" >&2; exit 2; }
[ ! -L "$BIN" ] || { echo "built recorder is symlink: $BIN" >&2; exit 2; }

INFO_SRC="$ROOT/$PACKAGE_PATH/out/signed/F1MacRecord.app/Contents/Info.plist"
[ -f "$INFO_SRC" ] || { echo "Info.plist template missing: $INFO_SRC" >&2; exit 2; }
APP="$OUT/F1MacRecord.app"
mkdir -p "$APP/Contents/MacOS"
cp -p "$BIN" "$APP/Contents/MacOS/F1MacRecord"
cp -p "$INFO_SRC" "$APP/Contents/Info.plist"

python3 - "$ROOT" "$OUT" "$PKG" "$SRC" "$BIN" "$APP/Contents/Info.plist" "$SWIFT_REAL" "$SWIFTC_REAL" "$XCRUN_REAL" "$build_rc" "$binpath_rc" <<'PY'
import hashlib, json, pathlib, sys
(root, out, pkg, src, binary, plist, swift, swiftc, xcrun,
 build_rc, binpath_rc) = sys.argv[1:]
out = pathlib.Path(out); pkg = pathlib.Path(pkg); src = pathlib.Path(src)
binary = pathlib.Path(binary); plist = pathlib.Path(plist)
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def item(p): return {"path": str(p), "sha256": digest(p), "bytes": p.stat().st_size}
manifest = {
  "kind": "sr0-generalized-mac-recorder-unsigned-build-v2",
  "sourceCommit": "0e201571e4320a3b6ccce14313fd2ad67e523904",
  "packagePath": "probes/sr0-o/f1-cross",
  "sourcePath": "probes/sr0-o/f1-cross/Sources/F1MacRecord/main.swift",
  "sourceSha256": digest(src),
  "packageSwiftSha256": digest(pkg / "Package.swift"),
  "sourceArchive": item(out / "source-archive.tar"),
  "compiler": {"xcrun": xcrun, "swift": swift, "swiftc": swiftc,
                "swiftBinary": item(pathlib.Path(swift)),
                "swiftcBinary": item(pathlib.Path(swiftc)),
                "xcrunBinary": item(pathlib.Path(xcrun))},
  "compilerVersionFiles": [item(out / "xcrun-version.txt"), item(out / "swift-version.txt"), item(out / "swiftc-version.txt")],
  "build": {"argv": ["xcrun", "swift", "build", "-c", "release", "--package-path", str(pkg), "--scratch-path", str(out / "swiftpm"), "--product", "F1MacRecord"], "exitCode": int(build_rc), "stdout": item(out / "swift-build.stdout"), "stderr": item(out / "swift-build.stderr")},
  "showBinPath": {"argv": ["xcrun", "swift", "build", "-c", "release", "--package-path", str(pkg), "--scratch-path", str(out / "swiftpm"), "--product", "F1MacRecord", "--show-bin-path"], "exitCode": int(binpath_rc), "stdout": item(out / "show-bin-path.stdout"), "stderr": item(out / "show-bin-path.stderr")},
  "binary": item(binary),
  "infoPlist": item(plist),
  "signing": "HELD-noninteractive-private-key-access-not-established",
}
(out / "unsigned-build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest, indent=2))
PY
