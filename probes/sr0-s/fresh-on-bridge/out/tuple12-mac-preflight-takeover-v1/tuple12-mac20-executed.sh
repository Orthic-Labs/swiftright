#!/bin/sh
# Strict Mac cross capture: 20 runs per config, internal-disk binaries only.
# Repo data may remain on /Volumes/D; no native binary may execute there.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${REC:?set REC to internal-disk signed F1MacRecord executable}"
: "${FA:?set FA to internal-disk FixtureApp executable}"
: "${ASM:?set ASM to internal-disk F1Assemble executable}"
OUT=${1:?usage: tuple12-mac20.sh OUT_DIR [CONFIG ...]}
shift
for p in "$REC" "$FA" "$ASM"; do
    [ -f "$p" ] || { echo "missing native input: $p" >&2; exit 2; }
    rp=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$p")
    case "$rp" in /Volumes/*) echo "refusing native input from mounted external volume: $rp" >&2; exit 2;; esac
done
REC_APP=${REC_APP:-$(CDPATH= cd -- "$(dirname -- "$REC")/../.." && pwd)}
[ -d "$REC_APP" ] || { echo "missing signed recorder app: $REC_APP" >&2; exit 2; }
REC_APP_REAL=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$REC_APP")
case "$REC_APP_REAL" in /Volumes/*) echo "refusing signed recorder app from mounted external volume: $REC_APP_REAL" >&2; exit 2;; esac
codesign --verify --deep --strict "$REC_APP" >/dev/null 2>&1 || { echo "signed recorder verification failed" >&2; exit 2; }
if [ "$#" -eq 0 ]; then
    set -- F1 F2 F3 F3-list-1s F3-list-3s F3-vstack-1s F3-vstack-3s F3-lazy-1s F3-lazy-3s F4 F5 F6 F6-reduced F7 F8 F9
fi
for c in "$@"; do
    [ -f "$ROOT/probes/sr0-o/f1-cross/cross/$c/steps-mac.json" ] || { echo "unknown Mac config: $c" >&2; exit 2; }
done
[ -e "$OUT" ] && { [ -d "$OUT" ] || { echo "output exists and is not directory: $OUT" >&2; exit 2; }; [ -z "$(find "$OUT" -mindepth 1 -print -quit)" ] || { echo "output must be fresh: $OUT" >&2; exit 2; }; }
mkdir -p "$OUT"
RUNS=${RUNS:-20}
[ "$RUNS" = 20 ] || { echo "RUNS must equal exactly 20" >&2; exit 2; }
for c in "$@"; do
    d="$OUT/$c"
    mkdir -p "$d"
    for i in $(seq 1 "$RUNS"); do
        tag="n$i"
        raw="$d/mac-raw-$tag.json"
        events="$d/mac-ev-$tag.jsonl"
        trace="$d/mac-trace-$tag.json"
        log="$d/mac-rec-$tag.log"
        if "$REC" --fixture "$FA" --events "$events" --out "$raw" --steps "$ROOT/probes/sr0-o/f1-cross/cross/$c/steps-mac.json" >"$log" 2>&1; then rec_rc=0; else rec_rc=$?; fi
        [ "$rec_rc" -eq 0 ] || { echo "$c $tag recorder exit=$rec_rc" >&2; exit 1; }
        if "$ASM" mac --raw "$raw" --events "$events" --stimulus "$ROOT/probes/sr0-o/f1-cross/cross/$c/stimulus.json" --out "$trace" --keep-lists >>"$log" 2>&1; then asm_rc=0; else asm_rc=$?; fi
        [ "$asm_rc" -eq 0 ] || { echo "$c $tag assembler exit=$asm_rc" >&2; exit 1; }
        [ -s "$raw" ] && [ -s "$events" ] && [ -s "$trace" ] || { echo "$c $tag missing receipt" >&2; exit 1; }
        echo "$c $tag PASS"
    done
done
