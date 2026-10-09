#!/bin/bash
# SR1 repeatability: each G configuration 20x through run-self-test.sh; outputs in out/sr1/.
# Usage: sr1-repeat20.sh [G1 ... G8]   (default: all). Progress in out/sr1/progress.log.
set -u
cd "$(dirname "$0")/.."
export OUT_DIR=out/sr1
mkdir -p "$OUT_DIR"
RUNS=${RUNS:-20}
ORDER=(G1 G2 G3 G4 G5 G6 G7 G8)
if [ $# -gt 0 ]; then ORDER=("$@"); fi
log="$OUT_DIR/progress.log"
# Single-instance guard: a second sweep would write the same run files and collide.
lock="$OUT_DIR/.sweep.pid"
if [ -f "$lock" ] && kill -0 "$(cat "$lock")" 2>/dev/null; then
  echo "sweep already running (pid $(cat "$lock")); refusing" >&2
  exit 1
fi
echo $$ > "$lock"
trap 'rm -f "$lock"' EXIT
for label in "${ORDER[@]}"; do
  for n in $(seq "$RUNS"); do
    rc=$(scripts/run-self-test.sh "$label" "$n" >/dev/null 2>&1; echo $?)
    echo "$(date +%H:%M:%S) $label run$n rc=$rc" >> "$log"
  done
done
echo "$(date +%H:%M:%S) DONE" >> "$log"
