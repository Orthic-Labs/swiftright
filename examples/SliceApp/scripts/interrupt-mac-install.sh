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
# Recovery check after either mode: re-run install-app for the new DMG into the same --dest and confirm
# `codesign --verify --deep --strict` + `spctl --assess` pass and rows.json is unchanged.
# No app is launched. Run from examples/SliceApp with the pinned right-release (pnpm exec). Needs the signed DMGs (R3).
set -eu
OLD=""; NEW=""; MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --old-dmg) OLD="$2"; shift 2 ;; --new-dmg) NEW="$2"; shift 2 ;; --mode) MODE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -f "$OLD" ] && [ -f "$NEW" ] || { echo "--old-dmg and --new-dmg must be existing files" >&2; exit 2; }
case "$MODE" in ditto|installer) ;; *) echo "--mode must be ditto or installer" >&2; exit 2 ;; esac
DEST=$(mktemp -d "${TMPDIR:-/tmp}/sliceapp-interrupt.XXXXXX")
install() { pnpm exec right-release install-app --dmg "$1" --app-name SliceApp.app --bundle-id dev.orthic.sliceapp --dest "$DEST" --no-relaunch; }
install "$OLD"
OLD_SUM=$(codesign -dv "$DEST/SliceApp.app" 2>&1 | grep -E '^(CDHash|Identifier)' | tr '\n' ' ')
echo "installed old: $OLD_SUM"
install "$NEW" &
PID=$!
# Wait for the replace phase: the installed bundle has been moved aside or ditto is running.
n=0
while [ $n -lt 600 ]; do
  if [ "$MODE" = ditto ] && pgrep -f "ditto .*SliceApp.app" >/dev/null 2>&1; then pkill -KILL -f "ditto .*SliceApp.app" || true; break; fi
  if [ "$MODE" = installer ] && [ ! -e "$DEST/SliceApp.app" ] && kill -0 "$PID" 2>/dev/null; then kill -KILL "$PID" || true; break; fi
  kill -0 "$PID" 2>/dev/null || break
  n=$((n+1)); sleep 0.05
done
wait "$PID" 2>/dev/null && RC=0 || RC=$?
echo "install-app exit=$RC (interrupt mode: $MODE)"
if [ -d "$DEST/SliceApp.app" ]; then
  codesign --verify --deep --strict "$DEST/SliceApp.app" && echo "dest bundle verifies" || echo "dest bundle FAILS verification"
  codesign -dv "$DEST/SliceApp.app" 2>&1 | grep -E '^(CDHash|Identifier)' | tr '\n' ' '; echo
else
  echo "dest bundle is ABSENT"
fi
ls -d "$HOME"/.Trash/SliceApp* 2>/dev/null || echo "no SliceApp bundle in ~/.Trash"
echo "scratch dest: $DEST (inspect, then remove it yourself)"
