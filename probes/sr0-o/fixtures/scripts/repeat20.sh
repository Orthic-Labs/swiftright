#!/bin/bash
# SR0-O repeatability: every configuration 20x through run-self-test.sh, outputs in out/repeat20/.
# Usage: repeat20.sh [config ...]   (default: all configs). Writes out/repeat20/progress.log.
set -u
cd "$(dirname "$0")/.."
export OUT_DIR=out/repeat20
mkdir -p "$OUT_DIR"
RUNS=${RUNS:-20}
# config label -> "<fixture-arg> <f3-variant or empty>" (bash 3.2 compatible: no associative arrays)
lookup() {
  case "$1" in
    F1) echo "F1 " ;; F2) echo "F2 " ;;
    F3-list-0s) echo "F3 " ;;
    F3-list-1s) echo "F3 list-1s" ;; F3-list-3s) echo "F3 list-3s" ;;
    F3-vstack-1s) echo "F3 vstack-1s" ;; F3-vstack-3s) echo "F3 vstack-3s" ;;
    F3-lazy-1s) echo "F3 lazy-1s" ;; F3-lazy-3s) echo "F3 lazy-3s" ;;
    F4) echo "F4 " ;; F5) echo "F5 " ;; F6) echo "F6 " ;;
    F6-reduced) echo "F6-reduced " ;; F7) echo "F7 " ;; F8) echo "F8 " ;; F9) echo "F9 " ;;
    *) echo "unknown config $1" >&2; exit 2 ;;
  esac
}
ORDER=(F1 F2 F3-list-0s F3-list-1s F3-list-3s F3-vstack-1s F3-vstack-3s F3-lazy-1s F3-lazy-3s F4 F5 F6 F6-reduced F7 F8 F9)
if [ $# -gt 0 ]; then ORDER=("$@"); fi
log="$OUT_DIR/progress.log"
for label in "${ORDER[@]}"; do
  read -r arg variant <<< "$(lookup "$label")"
  for n in $(seq "$RUNS"); do
    pkill -9 -f 'FixtureApp.*repeat20' 2>/dev/null  # only this sweep's instances
    sleep 1
    if [ -n "$variant" ]; then
      rc=$(scripts/run-self-test.sh "$arg" "$n" "$variant" >/dev/null 2>&1; echo $?)
    else
      rc=$(scripts/run-self-test.sh "$arg" "$n" >/dev/null 2>&1; echo $?)
    fi
    echo "$(date +%H:%M:%S) $label run$n rc=$rc" >> "$log"
  done
  pkill -9 -f 'FixtureApp.*repeat20' 2>/dev/null  # only this sweep's instances
done
echo "$(date +%H:%M:%S) DONE" >> "$log"
