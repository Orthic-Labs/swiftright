#!/bin/bash
# Runs the SR0-S fixture matrix on the Windows host, 3 runs per configuration. Each run is a one-shot
# interactive scheduled task (schedule-fixture.ps1). A run is retried only when the driver reports that
# the test window could not take the foreground (keys are never sent to another application); each
# attempt is kept under out/matrix/. Usage: run-matrix.sh [config ...]   (config = FIXTURE:VARIANT)
# OUT_DIR overrides the evidence directory, so a new pass does not overwrite an earlier one.
OUT="${OUT_DIR:-$(cd "$(dirname "$0")/.." && pwd)/out/matrix}"
mkdir -p "$OUT"
DEFAULT=("F1:none" "F2:none" "F3:list-0s" "F3:list-1s" "F3:vstack-1s" "F3:lazy-1s" "F4:none" "F5:none" "F6:none" "F6:reduced" "F6:override-on" "F7:none" "F8:none" "F9:none" "F9:notasks")
CONFIGS=("$@"); [ ${#CONFIGS[@]} -eq 0 ] && CONFIGS=("${DEFAULT[@]}")
for cfg in "${CONFIGS[@]}"; do
  F=${cfg%%:*}; V=${cfg#*:}
  for run in 1 2 3; do
    base="$OUT/${F}-${V}-r${run}"
    for attempt in 1 2 3 4 5 6 7 8; do
      tag="${F}${V//[^a-z0-9]/}r${run}a${attempt}"
      win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\\Claude\\sr0s-bridge\\probes\\sr0-s\\fresh-on-bridge\\scripts\\schedule-fixture.ps1 -Fixture $F -Variant $V -Tag $tag" > "$base.a$attempt.txt" 2>&1
      if grep -q "not_foreground\|no window: UIA root unavailable" "$base.a$attempt.txt"; then sleep 45; else break; fi
    done
    cp "$base.a$attempt.txt" "$base.txt"
    echo "$F $V run$run attempts=$attempt: $(grep -h '^SELFTEST ' "$base.txt" | tail -1)"
  done
done
