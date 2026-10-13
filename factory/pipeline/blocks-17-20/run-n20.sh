#!/bin/sh
# N=20 paired runs of every blocks-17-20 case on ONE staged product build.  usage: run-n20.sh <stage-name> [runs] [case...]
cd "$(dirname "$0")"
STAGE=$1; RUNS=${2:-20}; shift; shift
CASES=${*:-$(ls -d swiftui.*/*/ | sed 's:/$::')}
for c in $CASES; do
  echo "== $c"
  python3 ../../tools/pair.py "$c" --runs "$RUNS" --stage "$STAGE" --sandbox 2>&1 | tail -4
done
