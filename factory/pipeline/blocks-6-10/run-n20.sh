#!/bin/sh
# N=20 paired runs of every Toggle / disabled case on ONE staged product build.  usage: run-n20.sh <stage-name> [runs]
# (python3 factory/tools/stage-product.py prints the stage name; the Windows captures run in the minimised Sandbox worker.)
cd "$(dirname "$0")"
STAGE=$1; RUNS=${2:-20}
for c in swiftui.toggle/switch-on-v1 swiftui.toggle/switch-off-v1 swiftui.toggle/switch-labelled-on-v1 swiftui.toggle/checkbox-on-v1 swiftui.toggle/checkbox-off-v1 swiftui.toggle/checkbox-labelled-on-v1 \
         swiftui.disabled/toggle-on-disabled-v1 swiftui.disabled/toggle-off-disabled-v1 swiftui.disabled/checkbox-on-disabled-v1 swiftui.disabled/checkbox-off-disabled-v1; do
  echo "== $c"
  python3 ../../tools/pair.py "$c" --runs "$RUNS" --stage "$STAGE" --sandbox 2>&1 | tail -4
done
