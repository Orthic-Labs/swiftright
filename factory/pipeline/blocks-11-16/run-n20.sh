#!/bin/sh
# N paired runs of blocks-11-16 cases on ONE staged product build.  usage: run-n20.sh <stage-name> [runs] [case...]
cd "$(dirname "$0")"
STAGE=$1; RUNS=${2:-20}; shift; shift
CASES=${*:-$(ls -d swiftui.*/*/ | sed 's:/$::')}
for c in $CASES; do
  echo "== $c"
  python3 ../../tools/pair.py "$c" --runs "$RUNS" --stage "$STAGE" --sandbox 2>&1 | grep -v Deprecat | grep -v "return \[" | tail -5
done
