#!/bin/bash
# Usage: run-self-test.sh <F1..F9|F6-reduced> <run-index>
# Launch -> run self-test -> quit. Kills the process if it is still alive after 30 s.
# Relaunches only when the root view never reports root-appear (window not presented);
# every attempt is recorded in out/<name>-run<n>.launch.txt. A launched run that fails its assertions is not retried.
set -u
cd "$(dirname "$0")/.."
BIN="$(swift build --show-bin-path)/FixtureApp"
arg="$1"; run="$2"
fixture="${arg%-reduced}"
extra=()
[[ "$arg" == *-reduced ]] && extra=(--reduced-motion-variant)
name="${arg}-run${run}"
events="out/${name}.jsonl"; stdout="out/${name}.stdout"; launch="out/${name}.launch.txt"
: > "$launch"
for attempt in 1 2 3 4 5 6 7 8; do
  rm -f "$events"
  "$BIN" --fixture "$fixture" --events "$events" ${extra[@]+"${extra[@]}"} --self-test > "$stdout" 2>&1 &
  pid=$!
  appeared=0
  for _ in $(seq 8); do
    if grep -q '"root-appear"' "$events" 2>/dev/null; then appeared=1; break; fi
    kill -0 $pid 2>/dev/null || break
    sleep 1
  done
  if [ $appeared -eq 1 ]; then
    echo "attempt $attempt: root-appear" >> "$launch"
    break
  fi
  echo "attempt $attempt: no root-appear within 8 s, relaunch" >> "$launch"
  kill -9 $pid 2>/dev/null; wait $pid 2>/dev/null
  pkill -9 -f "FixtureApp --fixture $fixture" 2>/dev/null
  sleep 1
done
for _ in $(seq 30); do
  kill -0 $pid 2>/dev/null || break
  sleep 1
done
if kill -0 $pid 2>/dev/null; then
  echo "HUNG after 30 s, killed" >> "$launch"
  kill -9 $pid 2>/dev/null
  wait $pid 2>/dev/null
  echo "RC=124"
  exit 124
fi
wait $pid
rc=$?
echo "RC=$rc" >> "$launch"
echo "RC=$rc"
exit $rc
