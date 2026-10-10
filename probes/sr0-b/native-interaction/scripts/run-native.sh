#!/bin/bash
# SR0 lane R9: runs the native-interaction checks on the Dell desktop (Windows host) against the ABI 0.6 fixture build.
#   Real Microsoft Japanese IME composition (F7 core checks, F7live insert-above mid-composition via the exe's release hook, F8 identity under structural change) and Narrator.
#
# THIS TYPES REAL KEYS INTO THE DESKTOP SESSION and starts Narrator (audible). It refuses to start unless the desktop lane is
# confirmed free:  DESKTOP_LANE_FREE=1 sh run-native.sh [ime-f7] [ime-f7live] [ime-f8] [narrator]      (default: all three, in that order)
# Optional: BASE_DIR (default D:\Claude\sr0s-bridge06b), EXPECT_EXE_SHA256 / EXPECT_DLL_SHA256 (defaults = the pinned 0.6 tuple),
#           OUT_DIR (default ../out), TAG (default a timestamp).
# Steps: stage the scripts to <BASE_DIR>\probes\sr0-b\native-interaction\scripts, static check on the host (parse + compile,
# no input), preflight hash check, then one one-shot interactive scheduled task per check (schedule-native.ps1).
# Nothing is committed, branched or pushed by this script. The Mac GUI is never used.
BASE_DIR="${BASE_DIR:-D:\\Claude\\sr0-r08\\src}"
EXPECT_EXE_SHA256="${EXPECT_EXE_SHA256:-7673A2D5139172D890D3882D332C3C72321F2372D343319A1065CFEEEDFDB960}"
EXPECT_DLL_SHA256="${EXPECT_DLL_SHA256:-E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93}"
[ "${DESKTOP_LANE_FREE:-0}" = 1 ] || { echo "refused: set DESKTOP_LANE_FREE=1 once the Dell desktop lane is reserved for this run (no other GUI work, no person typing)" >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT_DIR:-$HERE/../out}"; mkdir -p "$OUT"
TAG="${TAG:-$(date +%Y%m%dT%H%M%S)}"
CHECKS=("$@"); [ ${#CHECKS[@]} -eq 0 ] && CHECKS=(ime-f7 ime-f7live ime-f8 narrator)
for c in "${CHECKS[@]}"; do case "$c" in ime-f7|ime-f7live|ime-f8|narrator) ;; *) echo "unknown check: $c" >&2; exit 2;; esac; done
for h in "$EXPECT_EXE_SHA256" "$EXPECT_DLL_SHA256"; do printf %s "$h" | grep -Eq '^[0-9A-Fa-f]{64}$' || { echo "expected hash is not 64 hex digits: $h" >&2; exit 2; }; done
WINDIR_SCRIPTS="$BASE_DIR\\probes\\sr0-b\\native-interaction\\scripts"
SCP_DIR="$(printf %s "$WINDIR_SCRIPTS" | tr '\\' '/')"

win "New-Item -ItemType Directory -Force -Path '$WINDIR_SCRIPTS' | Out-Null; 'staging dir ready'" || exit 1
scp -q "$HERE"/NativeHelpers.cs "$HERE"/*.ps1 "win:$SCP_DIR/" || { echo "staging failed" >&2; exit 1; }
win "powershell -NoProfile -ExecutionPolicy Bypass -File $WINDIR_SCRIPTS\\check-native.ps1" | tee "$OUT/static-check-$TAG.txt"
grep -q '^CHECK_OK' "$OUT/static-check-$TAG.txt" || { echo "static check failed; nothing was run" >&2; exit 2; }
win "powershell -NoProfile -ExecutionPolicy Bypass -File $BASE_DIR\\probes\\sr0-s\\fresh-on-bridge\\scripts\\verify-artifacts.ps1 -Base $BASE_DIR -ExpectExe $EXPECT_EXE_SHA256 -ExpectDll $EXPECT_DLL_SHA256" | tee "$OUT/preflight-$TAG.txt"
grep -q 'ARTIFACT_OK' "$OUT/preflight-$TAG.txt" || { echo "preflight refused: artifacts do not match the expected hashes; nothing was run" >&2; exit 2; }

for c in "${CHECKS[@]}"; do
  echo "=== $c ($TAG) ==="
  win "powershell -NoProfile -ExecutionPolicy Bypass -File $WINDIR_SCRIPTS\\schedule-native.ps1 -Base $BASE_DIR -Check $c -Tag $TAG -ExpectExe $EXPECT_EXE_SHA256 -ExpectDll $EXPECT_DLL_SHA256" > "$OUT/native-$c-$TAG.txt" 2>&1
  grep -E '^ *[0-9.]+s (CHECK|NATIVE_SUMMARY)' "$OUT/native-$c-$TAG.txt"
  grep -q 'NATIVE_SUMMARY' "$OUT/native-$c-$TAG.txt" || echo "no summary for $c (see $OUT/native-$c-$TAG.txt)"
done
