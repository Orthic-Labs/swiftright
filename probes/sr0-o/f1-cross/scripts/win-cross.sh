#!/bin/bash
# Mac-side driver for the Windows cross recordings. Takes D:\Claude\desktop.lock (waits, in this background loop, while
# another owner holds it), runs one interactive scheduled task per config/run, pulls the files, writes `free`.
#   [FIRST=1] win-cross.sh <local-out-dir> <last-run> <config>...        (tags are <config>-w<run>, runs FIRST..last-run)
set -u
OUT=$1; RUNS=$2; shift 2
LOCK='D:\Claude\desktop.lock'
OWNER=${OWNER:-cross11}
BIN=${BIN:-'D:\Claude\sr0-r11\src\scratch\out\Products\Release-windows-x86_64'}   # passed explicitly: the Dell copy of schedule-cross.ps1 keeps its own default
EXPECT_EXE=${EXPECT_EXE:-073513142f25c454b58dd05e545875e90b157539c72977e855ad68785293d55e}   # a run on any other exe aborts the batch
acquire() {
  win "\$l=(Get-Content -Raw $LOCK).Trim(); if (\$l -eq 'free') { Set-Content -NoNewline -Path $LOCK -Value ('$OWNER ' + (Get-Date -Format o)); 'ACQUIRED' } else { 'BUSY ' + \$l }" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
}
until r=$(acquire); [[ "$r" == ACQUIRED* ]]; do echo "lock busy: $r"; sleep 60; done
echo "lock acquired $(date)"
release() { win "Set-Content -NoNewline -Path $LOCK -Value 'free'" >/dev/null 2>&1; echo "lock released $(date)"; }
trap release EXIT
mkdir -p "$OUT"
for c in "$@"; do
  for i in $(seq "${FIRST:-1}" "$RUNS"); do
    tag="$c-${TAGP:-w}$i"
    win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\\Claude\\sr0o-f1\\scripts\\schedule-cross.ps1 -Config $c -Tag $tag -Bin $BIN" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$OUT/run-$tag.log"
    if ! grep -q "ARTIFACTS exe=$EXPECT_EXE" "$OUT/run-$tag.log"; then echo "ABORT $tag: the run did not use exe $EXPECT_EXE"; exit 3; fi
    for f in "winrec-$tag.json" "winside-$tag.json" "events-$tag.txt"; do
      win "Get-Content -Raw D:\\Claude\\sr0o-f1\\out\\$f" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$OUT/$f"
    done
    echo "$tag: $(grep -m1 'recorder exit' "$OUT/run-$tag.log") $(grep -m1 'wrote ' "$OUT/run-$tag.log" | cut -c1-120)"
  done
done
