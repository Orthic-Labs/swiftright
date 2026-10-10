#!/bin/bash
# Mac-side driver for the Windows cross recordings. Takes D:\Claude\desktop.lock (waits, in this background loop, while
# another owner holds it), runs one interactive scheduled task per config/run, pulls the files, writes `free`.
#   [FIRST=1] win-cross.sh <local-out-dir> <last-run> <config>...        (tags are <config>-w<run>, runs FIRST..last-run)
set -u
OUT=$1; RUNS=$2; shift 2
LOCK='D:\Claude\desktop.lock'
OWNER=T1
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
    tag="$c-w$i"
    win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\\Claude\\sr0o-f1\\scripts\\schedule-cross.ps1 -Config $c -Tag $tag" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$OUT/run-$tag.log"
    for f in "winrec-$tag.json" "winside-$tag.json" "events-$tag.txt"; do
      win "Get-Content -Raw D:\\Claude\\sr0o-f1\\out\\$f" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$OUT/$f"
    done
    echo "$tag: $(grep -m1 'recorder exit' "$OUT/run-$tag.log") $(grep -m1 'wrote ' "$OUT/run-$tag.log" | cut -c1-120)"
  done
done
