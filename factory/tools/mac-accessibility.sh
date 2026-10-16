#!/bin/bash
# Mac accessibility environment for factory captures (decision C12 extension). usage: mac-accessibility.sh <out-file>
# Logs the accessibility settings and screens, sets any setting that is on back to the reference (all off, as on Adrian's Mac on
# 2026-10-16), re-reads them through NSWorkspace, and FAILS CLOSED (exit 1) if any setting is still on or a readback line is missing.
# Reduce Motion turns movement transitions into crossfades, so an on setting changes the Mac reference.
set -uo pipefail
out="${1:?usage: mac-accessibility.sh <out-file>}"
here="$(cd "$(dirname "$0")" && pwd)"
keys="reduceMotion reduceTransparency increaseContrast differentiateWithoutColor"

# defaults: 1 = on; absent or 0 = off; anything else is reported raw and counts as on (fail closed)
read_default() {
  local v
  if v="$(defaults read com.apple.universalaccess "$1" 2>/dev/null)"; then
    case "$v" in 0|false|NO|no) echo 0 ;; 1|true|YES|yes) echo 1 ;; *) echo "raw:$v" ;; esac
  else
    echo absent
  fi
}
is_on() { [ "$1" = 1 ] || case "$1" in raw:*) return 0 ;; *) return 1 ;; esac; }

snapshot() {
  local label="$1" k
  echo "== $label"
  for k in $keys; do echo "defaults.$k=$(read_default "$k")"; done
  swift "$here/mac-accessibility.swift" 2>&1
  echo "sw_vers: $(sw_vers -productVersion) $(sw_vers -buildVersion)"
}

{
  snapshot before
  fixed=0
  for k in $keys; do
    v="$(read_default "$k")"
    if is_on "$v"; then
      echo "set $k: $v -> 0 (reference: off)"
      defaults write com.apple.universalaccess "$k" -bool false || echo "defaults write $k failed"
      fixed=1
    fi
  done
  [ "$fixed" = 1 ] && snapshot after-set
} | tee "$out"

# verification: every defaults key off and every NSWorkspace flag reported false
fail=0
for k in $keys; do
  v="$(read_default "$k")"
  if is_on "$v"; then echo "::error::accessibility $k is $v; the Mac reference requires off"; fail=1; fi
done
ws="$(swift "$here/mac-accessibility.swift" 2>&1)"
for k in reduceMotion reduceTransparency increaseContrast differentiateWithoutColor; do
  line="$(printf '%s\n' "$ws" | grep -E "^ax\.$k=" || true)"
  case "$line" in
    "ax.$k=false") ;;
    "ax.$k=true") echo "::error::NSWorkspace $k is on; the Mac reference requires off"; fail=1 ;;
    *) echo "::error::NSWorkspace readback for $k missing or unparsed: '$line'"; fail=1 ;;
  esac
done
if [ "$fail" != 0 ]; then echo "::error::Mac accessibility environment does not match the reference; capture refused" >&2; exit 1; fi
echo "mac accessibility environment matches the reference (all off)" | tee -a "$out"
