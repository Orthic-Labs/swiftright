#!/bin/sh
# R7 (macOS), @rightkit/release >= 0.2.141: interrupt the REAL `right-release install-app` in a scratch destination
# (never /Applications) and check what is left. 0.2.141+ stages a copy beside the install, journals, swaps with renames
# only, rolls back on SIGINT/SIGTERM, and `install-app --recover` finishes an interrupted install after a hard kill.
#
# usage: interrupt-mac-install.sh --old-dmg <0.1.0.dmg> --new-dmg <0.1.1.dmg> --mode copy|swap|swap-term
#   copy       SIGKILL install-app while ditto copies into the staging path.
#   swap       SIGKILL install-app right after installed -> backup (installed path absent).
#   swap-term  SIGTERM at the same point (signal rollback).
# Env: RIGHT_RELEASE (command, default "pnpm exec right-release"; e.g. "$HOME/r7/node $HOME/r7/node_modules/@rightkit/release/cli/right-release.mjs"),
#      SLICEAPP_DATA_DIR (rows.json directory, default ~/Library/Application Support/SliceApp), SLICEAPP_LAUNCH (1 = also
#      start the bundle for 4 s and require it to stay alive; default 1).
# Checks after the interrupt (before any recovery): app present + verifies + old/new, launchable, DMG mounts, leftovers
# (journal, staged, backup). Then `install-app --recover`, then the same checks. Exit: 0 all expectations met, 1 an
# expectation failed, 2 usage, 3 interruption did not fire.
set -u
OLD=""; NEW=""; MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --old-dmg) OLD="$2"; shift 2 ;; --new-dmg) NEW="$2"; shift 2 ;; --mode) MODE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -f "$OLD" ] && [ -f "$NEW" ] || { echo "--old-dmg and --new-dmg must be existing files" >&2; exit 2; }
case "$MODE" in copy|swap|swap-term) ;; *) echo "--mode must be copy, swap or swap-term" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/interrupt-mac-install-hook.mjs"
[ -f "$HOOK" ] || { echo "missing $HOOK" >&2; exit 2; }
RR=${RIGHT_RELEASE:-pnpm exec right-release}
DEST=$(mktemp -d "${TMPDIR:-/tmp}/sliceapp-interrupt.XXXXXX")
MARK="$DEST.mark.json"
DATA="${SLICEAPP_DATA_DIR:-$HOME/Library/Application Support/SliceApp}"
ROWS="$DATA/rows.json"
rows_sum() { if [ -f "$ROWS" ]; then shasum -a 256 "$ROWS" | awk '{print $1}'; else echo none; fi; }
install() { $RR install-app --dmg "$1" --app-name SliceApp.app --bundle-id dev.orthic.sliceapp --dest "$DEST" --no-relaunch; }
FAIL=0
expect() { if [ "$2" = ok ]; then echo "EXPECT PASS: $1"; else echo "EXPECT FAIL: $1"; FAIL=1; fi; }
cdhash() { codesign -dvvv "$1" 2>&1 | grep -E '^CDHash=' | head -1; }
version_of() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null || echo "?"; }
mounts() { hdiutil info | awk '/right-install-app-/ {print $NF}' | sort -u; }
leftovers() { ls -A "$DEST" | grep -v '^SliceApp.app$' || true; }
launch_check() {
  [ "${SLICEAPP_LAUNCH:-1}" = 1 ] || return 0
  EXE="$DEST/SliceApp.app/Contents/MacOS/SliceApp"
  [ -x "$EXE" ] || return 1
  SLICEAPP_DATA_DIR="$DATA" "$EXE" >/dev/null 2>&1 &
  LP=$!; sleep 4
  if kill -0 "$LP" 2>/dev/null; then kill "$LP" 2>/dev/null; sleep 1; kill -9 "$LP" 2>/dev/null; wait "$LP" 2>/dev/null; return 0; fi
  return 1
}
report() { # $1 label
  if [ -d "$DEST/SliceApp.app" ]; then
    if codesign --verify --deep --strict "$DEST/SliceApp.app" 2>/dev/null; then DV=1; else DV=0; fi
    echo "[$1] app present, verifies=$DV, version=$(version_of "$DEST/SliceApp.app"), $(cdhash "$DEST/SliceApp.app")"
    PRESENT=1
  else echo "[$1] app ABSENT"; PRESENT=0; DV=0; fi
  echo "[$1] leftovers in dest: $(leftovers | tr '\n' ' ')"
  echo "[$1] install-app mounts: $(mounts | tr '\n' ' ')"
}

install "$OLD" || { echo "initial install of the old DMG failed"; exit 1; }
OLD_CD=$(cdhash "$DEST/SliceApp.app"); OLD_V=$(version_of "$DEST/SliceApp.app")
launch_check && echo "old app launched and stayed alive 4 s" || echo "old app did not stay alive (seeding rows.json needs a launch)"
ROWS_BEFORE=$(rows_sum)
echo "installed old: v$OLD_V $OLD_CD rows.json sha256=$ROWS_BEFORE"
( NODE_OPTIONS="--import=$HOOK${NODE_OPTIONS:+ $NODE_OPTIONS}"; SLICEAPP_INTERRUPT="$MODE"; SLICEAPP_INTERRUPT_MARK="$MARK"; export NODE_OPTIONS SLICEAPP_INTERRUPT SLICEAPP_INTERRUPT_MARK; install "$NEW" )
RC=$?
echo "install-app exit=$RC (interrupt mode: $MODE)"
if [ ! -f "$MARK" ] || ! grep -q '"fired":true' "$MARK"; then echo "hook did not fire; nothing was interrupted"; echo "scratch dest: $DEST"; exit 3; fi
echo "hook: $(cat "$MARK")"
sleep 1
echo "--- after the interrupt, before any recovery"
report "post-interrupt"
if [ "$PRESENT" = 1 ] && [ "$DV" = 1 ]; then expect "app present and verifying right after the interrupt" ok
elif [ "$MODE" = swap ] && [ "$PRESENT" = 0 ]; then echo "OBSERVED: SIGKILL between the two swap renames leaves the install path absent until --recover (inherent to a hard kill; the backup is beside it)"
else expect "app present and verifying right after the interrupt" bad; fi
if [ "$PRESENT" = 1 ]; then launch_check && expect "app launches after the interrupt" ok || expect "app launches after the interrupt" bad; fi
[ -z "$(mounts)" ] && expect "DMG detached right after the interrupt" ok || echo "OBSERVED: DMG still mounted after the interrupt (a SIGKILL cannot run cleanup)"
echo "--- install-app --recover"
$RR install-app --recover --dest "$DEST" --app-name SliceApp.app --json; echo "recover exit=$?"
report "post-recover"
[ "$PRESENT" = 1 ] && [ "$DV" = 1 ] && expect "app present and verifying after --recover" ok || expect "app present and verifying after --recover" bad
[ -z "$(mounts)" ] && expect "DMG detached after --recover" ok || expect "DMG detached after --recover" bad
[ -z "$(leftovers)" ] && expect "no journal/staged/backup leftovers after --recover" ok || expect "no journal/staged/backup leftovers after --recover" bad
NOW_CD=$(cdhash "$DEST/SliceApp.app")
[ "$NOW_CD" = "$OLD_CD" ] && echo "OBSERVED: after --recover the installed app is the OLD bundle" || echo "OBSERVED: after --recover the installed app is v$(version_of "$DEST/SliceApp.app") ($NOW_CD)"
launch_check && expect "app launches after --recover" ok || expect "app launches after --recover" bad
[ "$(rows_sum)" = "$ROWS_BEFORE" ] && expect "rows.json unchanged ($ROWS_BEFORE)" ok || expect "rows.json unchanged" bad
echo "--- follow-up: uninterrupted install of the new DMG"
install "$NEW" && expect "uninterrupted install of the new DMG succeeds" ok || expect "uninterrupted install of the new DMG succeeds" bad
echo "final: v$(version_of "$DEST/SliceApp.app") rows.json=$(rows_sum)"
echo "scratch dest: $DEST (inspect, then remove it yourself)"
exit $FAIL
