#!/bin/sh
# macOS UI-only incremental build check (architecture section 11): zero Rust compiler invocations and identical engine/renderer
# artifact hashes after a screen-source edit. Shims for cargo/rustc/rustup/rightkit go first on PATH and log any call.
# Builds only (no GUI). Usage: build-incremental.sh [edits] [out.json] [engine-artifact ...]
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
EDITS=${1:-3}; OUT=${2:-$HERE/incremental-mac.json}; shift 2 2>/dev/null || true
SHIM=$(mktemp -d); LOG=$SHIM/shim.log; : > "$LOG"
for n in cargo rustc rustup rightkit rustdoc; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 97\n' "$n" "$LOG" > "$SHIM/$n"; chmod +x "$SHIM/$n"
done
export PATH="$SHIM:$PATH" RUSTC_WRAPPER="$SHIM/rustc"
TARGET=$HERE/Sources/WorkloadCore/WorkloadScreen.swift
cp "$TARGET" "$SHIM/orig.swift"
trap 'cp "$SHIM/orig.swift" "$TARGET"' EXIT
cd "$HERE"
swift build -c release --product WorkloadMac >/dev/null 2>&1   # warm
BIN=$(swift build -c release --show-bin-path)
hashes() { for f in "$@"; do [ -f "$f" ] && shasum -a 256 "$f"; done; }
BEFORE=$(hashes "$@")
TRIALS=""; RUST=0; OK=true
i=1
while [ "$i" -le "$EDITS" ]; do
  printf '\n// R10 incremental edit %s %s\n' "$i" "$(date -u +%FT%TZ)" >> "$TARGET"
  PRE=$(wc -l < "$LOG")
  S=$(date +%s)
  if swift build -c release --product WorkloadMac >/dev/null 2>&1; then RC=0; else RC=$?; OK=false; fi
  E=$(date +%s)
  POST=$(wc -l < "$LOG")
  INV=$((POST - PRE)); RUST=$((RUST + INV))
  TRIALS="$TRIALS{\"edit\":$i,\"exit\":$RC,\"seconds\":$((E - S)),\"rust_invocations\":$INV},"
  i=$((i + 1))
done
AFTER=$(hashes "$@")
IDENT=true; [ "$BEFORE" = "$AFTER" ] || IDENT=false
printf '{"platform":"macos","edits":%s,"trials":[%s],"rust_invocations_total":%s,"hashes_identical":%s,"builds_ok":%s,"artifacts_checked":%s,"note":"no Rust in the Mac workload path; check is trivially zero unless an engine artifact is passed"}\n' \
  "$EDITS" "${TRIALS%,}" "$RUST" "$IDENT" "$OK" "$#" > "$OUT"
cat "$OUT"
