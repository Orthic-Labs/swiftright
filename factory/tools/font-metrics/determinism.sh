#!/bin/zsh
# N-repeat determinism gate: runs font-metrics.sh N times (separate processes, variants rebuilt each time) and compares every output byte for byte with the first.
# usage: determinism.sh [N=20] [outdir]     prints one sha256 per run and "DETERMINISTIC n=N" or "NOT DETERMINISTIC".
n="${1:-20}"; out="${2:-${TMPDIR:-/tmp}/font-metrics-det}"; mkdir -p "$out"; here="${0:A:h}"
first=""; bad=0
for i in $(seq 1 $n); do
  "$here/font-metrics.sh" > "$out/run-$i.json" 2> "$out/run-$i.err" || { echo "run $i failed"; bad=1; continue; }
  h=$(shasum -a 256 "$out/run-$i.json" | cut -d' ' -f1); echo "run $i $h $(wc -c < "$out/run-$i.json") bytes"
  [ -z "$first" ] && first="$h"; [ "$h" = "$first" ] || bad=1
done
[ $bad = 0 ] && echo "DETERMINISTIC n=$n sha256=$first" || echo "NOT DETERMINISTIC"
exit $bad
