#!/bin/sh
# F6 (macOS): interrupt the REAL install/swap that `right-release install-app` performs, in a scratch destination
# (never /Applications). install-app (install-app.mjs "Replace") moves the installed bundle into ~/.Trash, runs
# `/usr/bin/ditto <mounted app> <dest>/SliceApp.app`, and only restores the old bundle when ditto reports an error.
#
# usage: interrupt-mac-install.sh --old-dmg <0.1.0.dmg> --new-dmg <0.1.1.dmg> --mode ditto|installer [--keep]
#   ditto      SIGKILL the ditto child while it copies: install-app sees ditto fail and runs its restore path.
#              Expect: install-app exits non-zero, <dest>/SliceApp.app is the old 0.1.0 bundle, codesign --verify passes.
#   installer  SIGKILL the install-app process itself right after the old bundle is moved aside (no cleanup code runs).
#              Expect (to be OBSERVED, not assumed): a missing or partial <dest>/SliceApp.app and the old bundle in
#              ~/.Trash. That outcome would be a RightKit defect (non-atomic swap): report it, do not fix it here.
# The interruption is injected by scripts/interrupt-mac-install-hook.mjs (NODE_OPTIONS --import into the real
# install-app process). R7 run 1 showed an external pgrep/kill poll never lands inside the ~50 ms swap. The script
# exits 3 when the hook did not fire (nothing was interrupted) so a missed interruption can never read as a pass.
# Recovery check after either mode: re-run install-app for the new DMG into the same --dest and confirm
# `codesign --verify --deep --strict` passes and rows.json (if present under ~/Library/Application Support/SliceApp) is
# unchanged. No app is launched. Run from examples/SliceApp with the pinned right-release (pnpm exec). Needs the DMGs.
# Env: SLICEAPP_DATA_DIR overrides the rows.json directory. Exit: 0 all expectations met, 1 an expectation failed,
# 2 usage, 3 interruption did not fire.
set -u
OLD=""; NEW=""; MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --old-dmg) OLD="$2"; shift 2 ;; --new-dmg) NEW="$2"; shift 2 ;; --mode) MODE="$2"; shift 2 ;;
    --keep) shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -f "$OLD" ] && [ -f "$NEW" ] || { echo "--old-dmg and --new-dmg must be existing files" >&2; exit 2; }
case "$MODE" in ditto|installer) ;; *) echo "--mode must be ditto or installer" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/interrupt-mac-install-hook.mjs"
[ -f "$HOOK" ] || { echo "missing $HOOK" >&2; exit 2; }
DEST=$(mktemp -d "${TMPDIR:-/tmp}/sliceapp-interrupt.XXXXXX")
MARK="$DEST.mark.json"
ROWS="${SLICEAPP_DATA_DIR:-$HOME/Library/Application Support/SliceApp}/rows.json"
rows_sum() { if [ -f "$ROWS" ]; then shasum -a 256 "$ROWS" | awk '{print $1}'; else echo none; fi; }
install() { pnpm exec right-release install-app --dmg "$1" --app-name SliceApp.app --bundle-id dev.orthic.sliceapp --dest "$DEST" --no-relaunch; }
FAIL=0
expect() { if [ "$2" = ok ]; then echo "EXPECT PASS: $1"; else echo "EXPECT FAIL: $1"; FAIL=1; fi; }
cdhash() { codesign -dvvv "$1" 2>&1 | grep -E '^CDHash=' | head -1; }

install "$OLD"
OLD_CD=$(cdhash "$DEST/SliceApp.app")
ROWS_BEFORE=$(rows_sum)
echo "installed old: $OLD_CD rows.json sha256=$ROWS_BEFORE"
# Subshell: a function-call env prefix would otherwise persist into the recovery install below.
( NODE_OPTIONS="--import=$HOOK${NODE_OPTIONS:+ $NODE_OPTIONS}"; SLICEAPP_INTERRUPT="$MODE"; SLICEAPP_INTERRUPT_MARK="$MARK"; export NODE_OPTIONS SLICEAPP_INTERRUPT SLICEAPP_INTERRUPT_MARK; install "$NEW" )
RC=$?
echo "install-app exit=$RC (interrupt mode: $MODE)"
[ -f "$MARK" ] && echo "hook: $(cat "$MARK")" || { echo "hook did not fire; nothing was interrupted"; echo "scratch dest: $DEST"; exit 3; }
grep -q '"fired":true' "$MARK" || { echo "hook reported no interruption"; echo "scratch dest: $DEST"; exit 3; }
if [ -d "$DEST/SliceApp.app" ]; then
  if codesign --verify --deep --strict "$DEST/SliceApp.app" 2>/dev/null; then echo "dest bundle verifies"; DV=1; else echo "dest bundle FAILS verification"; DV=0; fi
  AFTER_CD=$(cdhash "$DEST/SliceApp.app"); echo "dest after interrupt: $AFTER_CD"
else
  echo "dest bundle is ABSENT"; DV=0; AFTER_CD=absent
fi
ls -d "$HOME"/.Trash/SliceApp* 2>/dev/null || echo "no SliceApp bundle in ~/.Trash"
if [ "$MODE" = ditto ]; then
  [ "$RC" -ne 0 ] && expect "install-app exits non-zero after the ditto kill" ok || expect "install-app exits non-zero after the ditto kill" bad
  [ "$DV" = 1 ] && [ "$AFTER_CD" = "$OLD_CD" ] && expect "old 0.1.0 bundle restored and verifying" ok || expect "old 0.1.0 bundle restored and verifying" bad
else
  [ "$DV" = 1 ] && [ "$AFTER_CD" = "$OLD_CD" ] && echo "OBSERVED: installer kill left the old bundle in place" || echo "OBSERVED: installer kill left dest absent or not the old bundle ($AFTER_CD); old bundle is in ~/.Trash (non-atomic swap, RightKit finding)"
fi
# A killed install-app leaves its DMG attached (observed: later attach fails "Resource busy"). Detach those mounts first.
for mp in $(hdiutil info | awk '/right-install-app-/ {print $NF}' | sort -u); do
  case "$mp" in /*) echo "stale install-app mount left by the kill: $mp"; hdiutil detach "$mp" >/dev/null 2>&1 || hdiutil detach -force "$mp" >/dev/null 2>&1 ;; esac
done
# Recovery: re-run the update with no interruption.
install "$NEW" && expect "recovery install of the new DMG succeeds" ok || expect "recovery install of the new DMG succeeds" bad
codesign --verify --deep --strict "$DEST/SliceApp.app" 2>/dev/null && expect "recovered bundle verifies" ok || expect "recovered bundle verifies" bad
[ "$(rows_sum)" = "$ROWS_BEFORE" ] && expect "rows.json unchanged ($ROWS_BEFORE)" ok || expect "rows.json unchanged" bad
echo "scratch dest: $DEST (inspect, then remove it yourself)"
exit $FAIL
