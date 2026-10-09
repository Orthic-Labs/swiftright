#!/bin/bash
# Runs the SR0-S fixture matrix on the Windows host, RUNS runs per configuration (default 3). Each run is a one-shot
# interactive scheduled task (schedule-fixture.ps1). A run is retried only when the driver reports that the test window
# could not take the foreground (keys are never sent to another application); each attempt is kept under $OUT.
#
# Required (the script refuses to start without them):
#   BASE_DIR            Windows tree root that holds the build. Default: the 0.6b build, D:\Claude\sr0s-bridge06b
#   EXPECT_EXE_SHA256   SHA-256 of FreshOnBridge.exe in <BASE_DIR>\scratch\out\Products\Release-windows-x86_64.
#                       Default: 3593209A... (0.6b: Tab / Shift-Tab traversal, IME hooks, per-line stdout flush)
#   EXPECT_DLL_SHA256   SHA-256 of swiftright_render.dll in the same directory. Default: C80B9517... (ABI 0.6)
# Defaults are the pinned 0.6b tuple; override all three together when a newer build exists.
# Preflight (verify-artifacts.ps1) must pass before anything runs, and every run re-checks the hashes on the host.
# Every result file starts with an ARTIFACT line that binds base dir and both hashes; a run whose ARTIFACT line does
# not carry the expected hashes is recorded as ARTIFACT_MISMATCH and the matrix stops.
#
# Configurations: the SR0 set is the 16 configurations of the Mac SR0-O REPEAT20 table (class=sr0). Diagnostic
# variants (class=diagnostic, not part of the SR0 inventory) run only with DIAG=1 or when named explicitly.
#
# Usage: [BASE_DIR=D:\Claude\sr0s-bridge06b EXPECT_EXE_SHA256=... EXPECT_DLL_SHA256=...] [OUT_DIR=...] [RUNS=3] [DIAG=1] \
#          sh scripts/run-matrix.sh [FIXTURE:VARIANT ...]
# OUT_DIR overrides the evidence directory, so a new pass does not overwrite an earlier one.
: "${BASE_DIR:=D:\\Claude\\sr0s-bridge06b}"
: "${EXPECT_EXE_SHA256:=3593209A49BC540FD0FAB2EC7AD14390A60C9E30042D8B7E23852D48000D68BA}"
: "${EXPECT_DLL_SHA256:=C80B9517B044968F3E13EE9D92EEFC8704D000510B9A51B3245C885CE1A3FB30}"
EXPECT_EXE_SHA256=$(printf %s "$EXPECT_EXE_SHA256" | tr a-f A-F)
EXPECT_DLL_SHA256=$(printf %s "$EXPECT_DLL_SHA256" | tr a-f A-F)
for h in "$EXPECT_EXE_SHA256" "$EXPECT_DLL_SHA256"; do
  printf %s "$h" | grep -Eq '^[0-9A-F]{64}$' || { echo "expected hash is not 64 hex digits: $h" >&2; exit 2; }
done
SCRIPTS="$BASE_DIR\\probes\\sr0-s\\fresh-on-bridge\\scripts"
OUT="${OUT_DIR:-$(cd "$(dirname "$0")/.." && pwd)/out/matrix}"
mkdir -p "$OUT"

SR0=("F1:none" "F2:none" "F3:list-0s" "F3:list-1s" "F3:list-3s" "F3:vstack-1s" "F3:vstack-3s" "F3:lazy-1s" "F3:lazy-3s"
     "F4:none" "F5:none" "F6:none" "F6:reduced" "F7:none" "F8:none" "F9:none")
DIAGNOSTIC=("F6:override-on" "F9:notasks")

in_list() { local needle=$1; shift; local x; for x in "$@"; do [ "$x" = "$needle" ] && return 0; done; return 1; }

CONFIGS=("$@")
if [ ${#CONFIGS[@]} -eq 0 ]; then
  CONFIGS=("${SR0[@]}")
  [ "${DIAG:-0}" = 1 ] && CONFIGS+=("${DIAGNOSTIC[@]}")
fi
for cfg in "${CONFIGS[@]}"; do
  in_list "$cfg" "${SR0[@]}" "${DIAGNOSTIC[@]}" || { echo "unknown configuration: $cfg" >&2; exit 2; }
done

# Preflight: the tree must hold exactly the expected exe and renderer DLL before any run starts.
PRE="$OUT/preflight-$(date +%Y%m%dT%H%M%S).txt"
win "powershell -NoProfile -ExecutionPolicy Bypass -File $SCRIPTS\\verify-artifacts.ps1 -Base $BASE_DIR -ExpectExe $EXPECT_EXE_SHA256 -ExpectDll $EXPECT_DLL_SHA256" > "$PRE" 2>&1
cat "$PRE"
grep -q 'ARTIFACT_OK' "$PRE" || { echo "preflight refused: artifacts do not match the expected hashes; nothing was run" >&2; exit 2; }

for cfg in "${CONFIGS[@]}"; do
  F=${cfg%%:*}; V=${cfg#*:}
  CLASS=sr0; in_list "$cfg" "${DIAGNOSTIC[@]}" && CLASS=diagnostic
  for run in $(seq 1 "${RUNS:-3}"); do
    base="$OUT/${F}-${V}-r${run}"
    for attempt in 1 2 3 4 5 6 7 8; do
      tag="${F}${V//[^a-z0-9]/}r${run}a${attempt}"
      win "powershell -NoProfile -ExecutionPolicy Bypass -File $SCRIPTS\\schedule-fixture.ps1 -Base $BASE_DIR -Fixture $F -Variant $V -Tag $tag -Class $CLASS -ExpectExe $EXPECT_EXE_SHA256 -ExpectDll $EXPECT_DLL_SHA256" > "$base.a$attempt.txt" 2>&1
      if grep -q "not_foreground\|no window: UIA root unavailable" "$base.a$attempt.txt"; then sleep 45; else break; fi
    done
    cp "$base.a$attempt.txt" "$base.txt"
    art=$(grep -h '^ARTIFACT base=' "$base.txt" | tail -1)
    case "$art" in
      *"exe_sha256=$EXPECT_EXE_SHA256"*"dll_sha256=$EXPECT_DLL_SHA256"*) ;;
      *) echo "$F $V run$run ARTIFACT_MISMATCH: header does not carry the expected hashes ($art)"; exit 1 ;;
    esac
    echo "$F $V run$run class=$CLASS attempts=$attempt: $(grep -h '^SELFTEST ' "$base.txt" | tail -1)"
  done
done
