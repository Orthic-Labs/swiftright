#!/bin/sh
# macOS SR0 workload run (10 s warm-up + 3 x 60 s measured, each run a fresh app launch), driven by SckRecorder.
# MUST run in the GUI session of the dedicated Mac TEST USER, on a quiet host (no builds, no other windows, display
# awake, 60 Hz, display scale pinned). It opens windows. Do not run it in Adrian's session.
# One-time, by the test user: grant SckRecorder.app Screen Recording and Accessibility in System Settings > Privacy & Security
# (run once with `--request-permissions` to raise the prompts, then rerun).
# Usage: scripts/run-mac.sh [--instr full|light] [--runs 3] [--tag name] [--request-permissions]
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
# Bundles run from the one fixed install path written by package-mac.sh (rule 2026-10-17); never from a build dir.
OUTMAC=${OUTMAC:-$HOME/Applications/SwiftRight}
INSTR=full; RUNS=3; TAG=""; EXTRA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instr) INSTR=$2; shift 2;;
    --runs) RUNS=$2; shift 2;;
    --tag) TAG=$2; shift 2;;
    --request-permissions) EXTRA="--request-permissions"; shift;;
    *) echo "unknown arg $1" >&2; exit 2;;
  esac
done
[ -n "$TAG" ] || TAG="$(date +%Y%m%d-%H%M%S)-$INSTR"
ROOT="$HERE/runs/$TAG"; mkdir -p "$ROOT"
REC="$OUTMAC/SckRecorder.app/Contents/MacOS/SckRecorder"
APP="$OUTMAC/WorkloadMac.app/Contents/MacOS/WorkloadMac"
[ -x "$REC" ] && [ -x "$APP" ] || { echo "build first: scripts/package-mac.sh" >&2; exit 2; }
cp "$OUTMAC/build-mac.json" "$ROOT/build-mac.json"
BUSY=$(pgrep -lf 'swift-build|swift-frontend|swiftc|xcodebuild|rustc|cargo|clang|lld' | grep -v pgrep || true)
if [ -n "$BUSY" ]; then echo "host not quiet:"; echo "$BUSY"; exit 3; fi
{
  echo "user=$(id -un) uid=$(id -u) console=$(stat -f %Su /dev/console)"
  sw_vers; uname -m
  system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Resolution|Refresh|UI Looks|Display Type|Chipset" || true
  pmset -g 2>/dev/null | head -20
} > "$ROOT/host.txt"
caffeinate -d -i -w $$ &
i=1
while [ "$i" -le "$RUNS" ]; do
  echo "== run r$i ($INSTR)"
  "$REC" --app "$APP" --out "$ROOT/r$i" --run-id "r$i" --warmup-s 10 --measure-s 60 --instr "$INSTR" $EXTRA || echo "run r$i exited $?"
  i=$((i + 1)); sleep 5
done
python3 -I "$HERE/analysis/analyze_workload.py" --os macos --root "$ROOT" --out "$ROOT/report" | tee "$ROOT/analysis-console.txt"
