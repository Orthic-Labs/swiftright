#!/bin/sh
# N=20 paired runs of the block 12 (swiftui.binding) static cases on ONE staged product build.  usage: run-binding-n20.sh <stage> [runs]
cd "$(dirname "$0")"
STAGE=$1; RUNS=${2:-20}
for c in swiftui.binding/derived-toggle-v1 swiftui.binding/constant-v1 swiftui.binding/setter-transaction-v1; do
  echo "== $c"
  python3 ../../tools/pair.py "$c" --runs "$RUNS" --stage "$STAGE" --sandbox 2>&1 | tail -4
done
