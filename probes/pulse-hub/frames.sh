#!/bin/bash
# usage: frames.sh <out dir>  (after deploy.sh <work dir>): one job per frame k (0..23), counter set first; a blank (white) first frame is retried at a 15 s wait, twice.
HERE="$(cd "$(dirname "$0")" && pwd)"; OUT="$1"; mkdir -p "$OUT"
EXE='D:\Claude\swiftright\.factory-work\hosts\pulse-hub-20261015\package\scratch\x86_64-unknown-windows-msvc\release\FactoryProbe.exe'
RDR='D:\Claude\swiftright\.factory-work\inputs\renderer-0.7-baseline-22ad719b\swiftright_render.dll'
BLANK="${BLANK_SHA:-}"   # sha1 of a known blank capture (set from the first run's output); empty: no retry
for k in $(seq 0 23); do
  ok=""
  for try in 0 1 2; do
    wait=6000; [ $try -gt 0 ] && wait=15000
    "$HERE/setframe.sh" $k "$OUT/setframe-$k-$try" >/dev/null 2>&1
    HUB_WAIT_MS=$wait python3 "$HERE/render-frame.py" "$EXE" 1 "$OUT/k$k-$try" "$RDR" > "$OUT/k$k-$try.log" 2>&1
    h=$(shasum "$OUT/k$k-$try/native-01-hub.png" 2>/dev/null | cut -c1-40)
    if [ -n "$h" ] && [ "$h" != "$BLANK" ]; then ok="$try"; break; fi
  done
  echo "k$k ok-try=${ok:-NONE} $(grep -a -o 'frame=[0-9]* section=[a-z]* scheme=[a-z]*' "$OUT/k$k-${ok:-0}/host-01.stdout.txt" 2>/dev/null | head -1)"
done
echo FRAMESDONE
