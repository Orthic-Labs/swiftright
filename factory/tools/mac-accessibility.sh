#!/bin/bash
# Mac accessibility environment for factory captures (decision C12 extension). usage: mac-accessibility.sh <out-file>
# Logs the accessibility settings and screens. On a GitHub Actions runner (GITHUB_ACTIONS=true only) it sets any setting that is on back to
# the reference (all off, as on Adrian's Mac on 2026-10-16). On any other machine it NEVER writes defaults: it only reports, and it fails
# closed (exit 1) if a setting is on. It re-reads through NSWorkspace and fails closed if any setting is still on or a readback line is missing.
# Reduce Motion turns movement transitions into crossfades, so an on setting changes the Mac reference.
# Scroller style: a List whose rows overflow reserves a gutter only under legacy (always-visible) scrollers (H21). The required value is the effective
# style (NSScroller legacy). AppleShowScrollBars is logged, not required. Whether an overlay style takes a gutter is unproven (H21): every runner logged overlay before the pin, so the pin is a measured requirement. On a
# GitHub Actions runner only, a non-legacy style is set with `defaults write -g AppleShowScrollBars Always` and re-read; anywhere else it fails closed.
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

# global defaults (the scroller setting): the raw value, or "absent" (Automatic, the system default)
read_global() {
  local v
  if v="$(defaults read -g "$1" 2>/dev/null)"; then echo "$v"; else echo absent; fi
}

snapshot() {
  local label="$1" k
  echo "== $label"
  for k in $keys; do echo "defaults.$k=$(read_default "$k")"; done
  echo "defaults.AppleShowScrollBars=$(read_global AppleShowScrollBars)"
  swift "$here/mac-accessibility.swift" 2>&1
  echo "sw_vers: $(sw_vers -productVersion) $(sw_vers -buildVersion)"
}

{
  snapshot before
  fixed=0
  for k in $keys; do
    v="$(read_default "$k")"
    if is_on "$v"; then
      if [ "${GITHUB_ACTIONS:-}" = true ]; then
        echo "set $k: $v -> 0 (reference: off; GitHub Actions runner)"
        defaults write com.apple.universalaccess "$k" -bool false || echo "defaults write $k failed"
        fixed=1
      else
        echo "::error::accessibility $k is $v on this machine; this script never writes outside GitHub Actions (read-only here)"
      fi
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
# scroller style (H21): required legacy; AppleShowScrollBars is logged only
scroll_style() { swift "$here/mac-accessibility.swift" 2>&1 | grep -E '^ax\.scrollerStyle=' | head -1 || true; }
style_line="$(printf '%s\n' "$ws" | grep -E '^ax\.scrollerStyle=' | head -1 || true)"
echo "defaults.AppleShowScrollBars=$(read_global AppleShowScrollBars) (logged, not required)"
echo "scroller: ${style_line:-missing}"
if [ "$style_line" != "ax.scrollerStyle=legacy" ]; then
  if [ "${GITHUB_ACTIONS:-}" = true ]; then
    echo "set AppleShowScrollBars: $(read_global AppleShowScrollBars) -> Always (GitHub Actions runner; scroller style '${style_line:-missing}' is not legacy)"
    defaults write -g AppleShowScrollBars Always || echo "defaults write AppleShowScrollBars failed"
    style_line="$(scroll_style)"
    echo "re-read: defaults.AppleShowScrollBars=$(read_global AppleShowScrollBars); scroller: ${style_line:-missing}"
  fi
  if [ "$style_line" != "ax.scrollerStyle=legacy" ]; then
    echo "::error::scroller style is '${style_line:-missing}'; the Mac reference requires legacy scrollers (H21); on a local Mac this is refused, not written"; fail=1
  fi
fi
if [ "$fail" != 0 ]; then echo "::error::Mac accessibility environment does not match the reference; capture refused" >&2; exit 1; fi
echo "mac accessibility environment matches the reference (all off)" | tee -a "$out"
