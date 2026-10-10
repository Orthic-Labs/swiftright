#!/bin/bash
# Interleaved full/light Mac workload runs (R10 / U2): F1 L1 F2 L2 F3 L3, each a fresh app launch driven by SckRecorder, with a
# resource sampler beside each run. Everything under $ROOT (scratch, internal disk). Usage: run_mac_ab.sh <tag>
set -u
W=/private/tmp/claude-501/-Volumes-D-claude-swiftright/608d5b75-d927-4ac2-a450-cee48f9d74ed/scratchpad/mac-workload
TAG=$1
OUTMAC=$W/out-mac
REC=$OUTMAC/SckRecorder.app/Contents/MacOS/SckRecorder
APP=$OUTMAC/WorkloadMac.app/Contents/MacOS/WorkloadMac
RF=$W/runs/$TAG-full
RL=$W/runs/$TAG-light
mkdir -p "$RF" "$RL"
for R in "$RF" "$RL"; do
  cp "$OUTMAC/build-mac.json" "$R/build-mac.json"
  {
    echo "user=$(id -un) uid=$(id -u) console=$(stat -f %Su /dev/console)"
    date -u +%FT%TZ
    sw_vers; uname -m
    echo "model=$(sysctl -n hw.model) cpu=$(sysctl -n machdep.cpu.brand_string) ncpu=$(sysctl -n hw.ncpu) mem_bytes=$(sysctl -n hw.memsize)"
    system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Resolution|UI Looks|Display Type|Chipset|Refresh|Total Number"
    pmset -g 2>/dev/null | head -20
    pmset -g batt | head -2
    uptime
    echo "--- top CPU processes at start"
    ps -axo pid,%cpu,comm | sort -k2 -nr | head -8
  } > "$R/host.txt"
done
caffeinate -d -i -w $$ &
CAFF=$!
for i in 1 2 3; do
  for lvl in full light; do
    if [ "$lvl" = full ]; then R=$RF; else R=$RL; fi
    echo "== $(date +%T) run r$i ($lvl) load: $(sysctl -n vm.loadavg)"
    mkdir -p "$R/r$i"
    python3 -I "$W/mac_sampler.py" --out "$R/r$i/resources.csv" --proc WorkloadMac --max-s 200 &
    SP=$!
    "$REC" --app "$APP" --out "$R/r$i" --run-id "r$i" --warmup-s 10 --measure-s 60 --instr "$lvl" || echo "run r$i ($lvl) exited $?"
    sleep 2
    kill -TERM $SP 2>/dev/null; wait $SP 2>/dev/null
    sleep 5
  done
done
kill $CAFF 2>/dev/null
echo "== done $(date +%T)"
