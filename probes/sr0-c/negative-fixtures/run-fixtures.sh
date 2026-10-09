#!/bin/sh
# Builds each target separately and prints: target | exit code | first compiler diagnostic.
# Usage: run-fixtures.sh <package-dir>   (negative targets must exit non-zero)
cd "$1" || exit 2
esc=$(printf '\033')
log=$(mktemp)
for t in PositiveControl NegOnReceive NegObservableObject NegTimerPublish; do
  swift build --target "$t" > "$log" 2>&1; rc=$?
  first=$(sed "s/$esc\[[0-9;]*m//g" "$log" | grep -m1 -E '\.swift:[0-9]+:[0-9]+: error:' || true)
  echo "$t | exit=$rc | ${first:-<no diagnostic>}"
done
rm -f "$log"
