#!/bin/sh
# Tuple 12 x20 cross-compare: Mac run n<i> vs Windows run t12<i>, per config, with cross/<c>/adapt-v0.json; plus repeatability per side.
set -u
R=/Volumes/D/claude/swiftright
X=$R/probes/sr0-o/f1-cross/cross
W1=$R/probes/sr0-s/fresh-on-bridge/out/tuple12-cross20-r1
W2=$R/probes/sr0-s/fresh-on-bridge/out/tuple12-cross20-r2
S=$HOME/sr0-scratch/sr-refs-host
ASM=$S/bin/F1Assemble
CMP=$S/cmp-src/.build/release/sr0o-trace
OUT=$S/xcmp
mkdir -p "$OUT"
for c in F1 F2 F3 F3-list-1s F3-list-3s F3-vstack-1s F3-vstack-3s F3-lazy-1s F3-lazy-3s F4 F5 F6 F6-reduced F7 F8 F9; do
  o=$OUT/$c; mkdir -p "$o"; pass=0; fail=0; asmfail=0
  for i in $(seq 1 20); do
    t=t12$i; W=$W1; [ -f "$W2/winrec-$c-$t.json" ] && W=$W2
    if ! "$ASM" win --rec "$W/winrec-$c-$t.json" --side "$W/winside-$c-$t.json" --events "$W/events-$c-$t.txt" \
         --stimulus "$X/$c/stimulus.json" --out "$o/win-trace-$t.json" --keep-lists >"$o/win-asm-$t.log" 2>&1; then
      asmfail=$((asmfail+1)); continue
    fi
    if "$CMP" compare "$S/mac20/$c/mac-trace-n$i.json" "$o/win-trace-$t.json" --adapt "$X/$c/adapt-v0.json" >"$o/cmp-n$i-$t.json" 2>"$o/cmp-n$i-$t.err"; then
      pass=$((pass+1)); else fail=$((fail+1)); fi
  done
  "$CMP" repeat "$S"/mac20/$c/mac-trace-n*.json >"$o/repeat-mac.txt" 2>&1; rm_=$?
  "$CMP" repeat "$o"/win-trace-t12*.json >"$o/repeat-win.txt" 2>&1; rw=$?
  echo "$c pass=$pass fail=$fail asmfail=$asmfail repeat_mac=$rm_ repeat_win=$rw"
done
