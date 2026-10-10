#!/bin/bash
# One Mac workload run with the sampler: run_one.sh <root> <rN> <full|light>
set -u
W=/private/tmp/claude-501/-Volumes-D-claude-swiftright/608d5b75-d927-4ac2-a450-cee48f9d74ed/scratchpad/mac-workload
OUTMAC=$W/out-mac
ROOT=$1; RID=$2; LVL=$3
mkdir -p "$ROOT/$RID"
cp "$OUTMAC/build-mac.json" "$ROOT/build-mac.json"
[ -f "$ROOT/host.txt" ] || { date -u +%FT%TZ; uptime; ps -axo pid,%cpu,comm | sort -k2 -nr | head -8; } > "$ROOT/host.txt"
caffeinate -d -i -w $$ &
CAFF=$!
echo "== $(date +%T) run $RID ($LVL) load: $(sysctl -n vm.loadavg)"
python3 -I "$W/mac_sampler.py" --out "$ROOT/$RID/resources.csv" --proc WorkloadMac --max-s 200 &
SP=$!
"$OUTMAC/SckRecorder.app/Contents/MacOS/SckRecorder" --app "$OUTMAC/WorkloadMac.app/Contents/MacOS/WorkloadMac" --out "$ROOT/$RID" --run-id "$RID" --warmup-s 10 --measure-s 60 --instr "$LVL" || echo "run $RID ($LVL) exited $?"
sleep 2
kill -TERM $SP 2>/dev/null; wait $SP 2>/dev/null
kill $CAFF 2>/dev/null
echo "== done $(date +%T)"
