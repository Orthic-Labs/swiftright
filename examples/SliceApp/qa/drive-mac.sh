#!/bin/sh
# SliceApp QA driver (macOS). Called from rightkit-qa scenarios (qa/scenarios/macos/*.scenario.toml) as
#   qa/drive-mac.sh <selfcheck|build|launch|journey>
# with the working directory examples/SliceApp. Contract: stdout carries exactly ONE JSON object (the step result the scenario
# asserts on), every log line goes to stderr, exit code 0 only when result.ok is true.
#
# HEADLESS HOST RULE: this script never launches SliceApp on the host Mac (it is Adrian's working machine). The app only ever runs
# inside a disposable Tart VM: cloned from $SLICEAPP_QA_VM_BASE, run with --no-graphics, deleted on exit. The host only builds
# (swift build, headless) and orchestrates over ssh. `selfcheck` and `build` touch no VM and open no window.
#
# Why the VM and not the host: right-release qa MACs its receipt with a key held by the host that runs it, so the receipt must
# be written by the host that later runs `right-release build`; this script is what lets that host test the app elsewhere.
#
# What the VM proves, and what it does not: window geometry (CGWindowList: owner pid, bounds, layer) and the quit request
# (NSRunningApplication.terminate) need no TCC permission. UI INPUT would need Accessibility granted to the probe in the VM image,
# which is not set up, so the journey edits rows.json between two launches instead of typing (result.uiDriven=false,
# result.dataWrittenBy="driver"). It proves the app launches, shows a window, writes its seed rows, quits on request, and
# survives a restart over edited data without rewriting it; it does not prove the UI shows the edited row.
#
# Not implemented: RIGHT_RELEASE_QA_STAGE=installed (refused; no false installed receipt).
#
# Environment (defaults match the clean-Mac-VM setup on this Mac):
#   SLICEAPP_QA_TART     tart binary     /Volumes/D/tart-install/dl/tart.app/Contents/MacOS/tart
#   TART_HOME            VM storage      /Volumes/D/tart-home
#   SLICEAPP_QA_VM_BASE  base VM         sliceapp-base   (vanilla macOS 26 + admin ssh key + Gatekeeper enabled)
#   SLICEAPP_QA_VM_KEY   ssh key         /Volumes/D/tart-home/keys/vmkey
set -u

CASE="${1:-}"
HERE=$(cd "$(dirname "$0")" && pwd)
APP_DIR=$(cd "$HERE/.." && pwd)
BUNDLE_ID="dev.orthic.sliceapp"
APP="$APP_DIR/dist/mac/SliceApp.app"
PROBE_SRC="$HERE/mac-probe.swift"
PROBE="$APP_DIR/.build/qa/mac-probe"
BUILD_RECORD="$APP_DIR/.build/qa-build.json"
TART="${SLICEAPP_QA_TART:-/Volumes/D/tart-install/dl/tart.app/Contents/MacOS/tart}"
export TART_HOME="${TART_HOME:-/Volumes/D/tart-home}"
VM_BASE="${SLICEAPP_QA_VM_BASE:-sliceapp-base}"
VM_KEY="${SLICEAPP_QA_VM_KEY:-/Volumes/D/tart-home/keys/vmkey}"
VM="sliceapp-qa-$$"
VM_CREATED=""
VM_PID=""
IP=""
SSH_OPTS="-i $VM_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 -o BatchMode=yes"
FIELDS=""
OK=false
ERROR=""
EMITTED=""

log() { printf '[sliceapp-qa] %s\n' "$*" >&2; }

# ---- JSON output (no jq on a stock Mac: plutil reads JSON, printf writes it)
jstr() { printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN { printf "\"" } { printf "%s", $0 } END { printf "\"" }'; }
add() { v="$2"; [ -n "$v" ] || v=null; FIELDS="$FIELDS${FIELDS:+,}\"$1\":$v"; }
add_str() { add "$1" "$(jstr "$2")"; }
add_json() { add "$1" "$(printf '%s' "$2" | tr -d '\n')"; }
json_get() { printf '%s' "$1" | plutil -extract "$2" raw -o - - 2>/dev/null; }
# jv: a value read out of a probe JSON, as a JSON token (null when absent); jraw: an embedded JSON object (null when empty).
jv() { v=$(json_get "$1" "$2"); if [ -n "$v" ]; then printf '%s' "$v"; else printf null; fi; }
jraw() { if [ -n "$1" ]; then printf '%s' "$1" | tr -d '\n'; else printf null; fi; }

emit_and_exit() {
  [ -z "$EMITTED" ] || exit 1
  EMITTED=1
  if [ -n "$ERROR" ]; then OK=false; fi
  printf '{"ok":%s,"case":"%s","platform":"macos","error":%s,"stage":%s,"commit":%s,%s}\n' \
    "$OK" "$CASE" "$([ -n "$ERROR" ] && jstr "$ERROR" || echo null)" "$(jstr "${RIGHT_RELEASE_QA_STAGE:-manual}")" "$(jstr "${COMMIT:-}")" \
    "${FIELDS:+$FIELDS,}\"diagnostics\":${DIAG:-[]}"
  [ "$OK" = true ] && exit 0
  exit 1
}
die() { ERROR="$1"; log "FAILED: $1"; emit_and_exit; }

# ---- VM lifecycle (only the VM this run cloned is ever stopped or deleted)
vm() { ssh $SSH_OPTS "admin@$IP" "$@"; }

vm_down() {
  [ -n "$VM_CREATED" ] || return 0
  "$TART" stop "$VM" >/dev/null 2>&1
  [ -z "$VM_PID" ] || wait "$VM_PID" 2>/dev/null
  case "$VM" in sliceapp-qa-*) "$TART" delete "$VM" >/dev/null 2>&1 ;; esac
  VM_CREATED=""
}
trap vm_down EXIT
trap 'vm_down; exit 130' INT TERM

vm_up() {
  [ -x "$TART" ] || die "tart not found or not executable: $TART (set SLICEAPP_QA_TART)"
  [ -f "$VM_KEY" ] || die "VM ssh key not found: $VM_KEY (set SLICEAPP_QA_VM_KEY)"
  "$TART" get "$VM_BASE" >/dev/null 2>&1 || die "base VM $VM_BASE not found in TART_HOME=$TART_HOME"
  log "cloning $VM_BASE -> $VM"
  "$TART" clone "$VM_BASE" "$VM" >&2 || die "tart clone failed"
  VM_CREATED=1
  "$TART" run --no-graphics "$VM" >"${TMPDIR:-/tmp}/$VM.log" 2>&1 &
  VM_PID=$!
  IP=$("$TART" ip --wait 120 "$VM" 2>/dev/null) || die "the VM got no IP address within 120 s"
  n=0
  until vm true 2>/dev/null; do
    n=$((n + 1)); [ $n -lt 60 ] || die "ssh to the VM ($IP) did not come up within 120 s"
    sleep 2
  done
  log "VM $VM up at $IP"
}

vm_install() {
  [ -d "$APP" ] || die "SliceApp.app not built: $APP (the build case must run first)"
  tar -C "$APP_DIR/dist/mac" -cf - SliceApp.app | vm 'rm -rf qa && mkdir -p qa && tar -C qa -xf -' || die "copying SliceApp.app into the VM failed"
  vm 'cat > qa/mac-probe && chmod +x qa/mac-probe' < "$PROBE" || die "copying the probe into the VM failed"
}

ROWS_PATH='$HOME/Library/Application Support/SliceApp/rows.json'
probe() { vm "qa/mac-probe $*" 2>/dev/null | tr -d '\n'; }
probe_rows() { vm "qa/mac-probe rows \"$ROWS_PATH\"" 2>/dev/null | tr -d '\n'; }

# Opens the app in the VM's GUI session and waits for a visible window. Sets STATE.
app_launch() {
  vm 'open -n qa/SliceApp.app' >&2 || die "open failed in the VM (no GUI session for the ssh user? enable auto-login in the base VM)"
  n=0
  while [ $n -lt 60 ]; do
    STATE=$(probe state "$BUNDLE_ID")
    if [ "$(json_get "$STATE" guiSession)" = false ]; then die "the VM ssh session has no window-server session: window geometry cannot be read (enable auto-login in $VM_BASE, or run the probe via launchctl asuser)"; fi
    [ "$(json_get "$STATE" windowShown)" = true ] && return 0
    n=$((n + 1)); sleep 1
  done
  return 1
}

app_quit() { probe quit "$BUNDLE_ID" 20; }

crash_reports() { vm 'ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c "^SliceApp" || true' 2>/dev/null | tr -d '[:space:]'; }

# ---- common
cd "$APP_DIR" || die "cannot enter $APP_DIR"
COMMIT=$(git -C "$APP_DIR" rev-parse HEAD 2>/dev/null || true)
DIAG='[]'
[ "${RIGHT_RELEASE_QA_STAGE:-}" != installed ] || die "installed-stage QA is not implemented for SliceApp: this driver tests the staged source build only, so no installed receipt can be produced"
if [ -n "${RIGHT_RELEASE_QA_COMMIT:-}" ] && [ "$RIGHT_RELEASE_QA_COMMIT" != "$COMMIT" ]; then die "RIGHT_RELEASE_QA_COMMIT $RIGHT_RELEASE_QA_COMMIT differs from the checkout HEAD $COMMIT"; fi

assert_build() {
  [ -f "$BUILD_RECORD" ] || die "no .build/qa-build.json: the build case (app.build scenario) must run first"
  rec_commit=$(plutil -extract commit raw -o - "$BUILD_RECORD" 2>/dev/null)
  [ "$rec_commit" = "$COMMIT" ] || die "staged build is for commit $rec_commit, checkout is $COMMIT"
  now=$(shasum -a 256 "$APP/Contents/MacOS/SliceApp" 2>/dev/null | cut -d' ' -f1)
  [ "$now" = "$(plutil -extract exeSha256 raw -o - "$BUILD_RECORD" 2>/dev/null)" ] || die "staged SliceApp changed since the build case recorded it"
  add_json build "{\"commit\":$(jstr "$rec_commit"),\"exeSha256\":$(jstr "$now")}"
}

case "$CASE" in
selfcheck)
  # No VM, no window, no build: tools and VM image presence only.
  have() { command -v "$1" >/dev/null 2>&1 && echo true || echo false; }
  add_json tools "{\"swift\":$(have swift),\"swiftc\":$(have swiftc),\"node\":$(have node),\"pnpm\":$(have pnpm),\"plutil\":$(have plutil),\"ssh\":$(have ssh),\"codesign\":$(have codesign)}"
  add tartPresent "$([ -x "$TART" ] && echo true || echo false)"
  add vmKeyPresent "$([ -f "$VM_KEY" ] && echo true || echo false)"
  if [ -x "$TART" ] && "$TART" get "$VM_BASE" >/dev/null 2>&1; then add baseVmPresent true; else add baseVmPresent false; fi
  add stagedAppExists "$([ -d "$APP" ] && echo true || echo false)"
  add probeExists "$([ -x "$PROBE" ] && echo true || echo false)"
  add_str vmBase "$VM_BASE"
  add_str tart "$TART"
  [ "$(plutil -extract ok raw -o - - <<EOF 2>/dev/null
{"ok":true}
EOF
)" = true ] || die "plutil cannot read JSON on this host"
  OK=true
  ;;

build)
  log "swift build -c release"
  swift build -c release >&2 || die "swift build failed"
  log "assembling dist/mac/SliceApp.app (unsigned) and ad-hoc signing it for the VM"
  pnpm exec right-release swift-package mac-app --config swift-package.json >&2 || die "swift-package mac-app failed"
  [ -d "$APP" ] || die "mac-app did not produce $APP"
  codesign --force --deep --sign - "$APP" >&2 || die "ad-hoc codesign of the QA bundle failed"
  mkdir -p "$APP_DIR/.build/qa"
  swiftc -O "$PROBE_SRC" -o "$PROBE" >&2 || die "compiling the VM probe failed"
  exe_sha=$(shasum -a 256 "$APP/Contents/MacOS/SliceApp" | cut -d' ' -f1)
  printf '{"commit":%s,"exeSha256":%s}\n' "$(jstr "$COMMIT")" "$(jstr "$exe_sha")" > "$BUILD_RECORD"
  add_json build "{\"commit\":$(jstr "$COMMIT"),\"exeSha256\":$(jstr "$exe_sha")}"
  OK=true
  ;;

launch)
  assert_build
  [ -x "$PROBE" ] || die "probe not built: $PROBE"
  vm_up
  vm_install
  app_launch || die "no visible SliceApp window within 60 s in the VM (state: $STATE)"
  wait_n=0; ROWS=$(probe_rows)
  while [ "$(json_get "$ROWS" rowCount)" != 5 ] && [ $wait_n -lt 15 ]; do wait_n=$((wait_n + 1)); sleep 1; ROWS=$(probe_rows); done
  QUIT=$(app_quit)
  CRASHES=$(crash_reports)
  add pid "$(jv "$STATE" pid)"
  add windowShown "$(jv "$STATE" windowShown)"
  add ready "$([ "$(json_get "$ROWS" rowCount)" = 5 ] && echo true || echo false)"
  add rowCount "$(jv "$ROWS" rowCount)"
  add_json window "$(jraw "$STATE")"
  add_json rowsJson "$(jraw "$ROWS")"
  add_json quit "{\"clean\":$([ "$(json_get "$QUIT" terminated)" = true ] && [ "${CRASHES:-0}" = 0 ] && echo true || echo false),\"detail\":$(jraw "$QUIT"),\"crashReports\":${CRASHES:-0}}"
  add_str exitCodeNote "exit status is not observable for an app started through open; clean = terminated on request and no SliceApp crash report"
  add_str vm "$VM"
  [ "$(json_get "$STATE" windowShown)" = true ] && [ "$(json_get "$ROWS" schema)" = 1 ] && [ "$(json_get "$ROWS" rowCount)" = 5 ] && [ "$(json_get "$QUIT" terminated)" = true ] && [ "${CRASHES:-0}" = 0 ] && OK=true
  [ "$OK" = true ] || ERROR="launch checks failed: see the JSON fields"
  ;;

journey)
  assert_build
  [ -x "$PROBE" ] || die "probe not built: $PROBE"
  commit8=$(printf '%s' "$COMMIT" | cut -c1-8)
  MARKER="qa-journey-$commit8-$(date +%H%M%S)"
  vm_up
  vm_install
  app_launch || die "first run: no visible SliceApp window within 60 s (state: $STATE)"
  STATE1="$STATE"
  wait_n=0; ROWS1=$(probe_rows)
  while [ "$(json_get "$ROWS1" rowCount)" != 5 ] && [ $wait_n -lt 15 ]; do wait_n=$((wait_n + 1)); sleep 1; ROWS1=$(probe_rows); done
  QUIT1=$(app_quit)
  EDIT=$(vm "qa/mac-probe setrow \"$ROWS_PATH\" 0 \"$MARKER\"" 2>/dev/null | tr -d '\n')
  ROWS_EDITED=$(probe_rows)
  app_launch || die "second run: no visible SliceApp window within 60 s (state: $STATE)"
  STATE2="$STATE"
  sleep 3
  ROWS2=$(probe_rows)
  QUIT2=$(app_quit)
  CRASHES=$(crash_reports)
  kept=false
  if printf '%s' "$ROWS2" | grep -q "\"$MARKER\"" && [ "$(json_get "$ROWS2" rowCount)" = 5 ] && [ "$ROWS2" = "$ROWS_EDITED" ]; then kept=true; fi
  add_str marker "$MARKER"
  add uiDriven false
  add_str dataWrittenBy driver
  add_json firstRun "{\"windowShown\":$(jv "$STATE1" windowShown),\"rowCount\":$(jv "$ROWS1" rowCount),\"quit\":$(jraw "$QUIT1"),\"rowsJson\":$(jraw "$ROWS1")}"
  add_json edit "{\"result\":$(jraw "$EDIT"),\"rowsJsonAfterEdit\":$(jraw "$ROWS_EDITED")}"
  add_json secondRun "{\"windowShown\":$(jv "$STATE2" windowShown),\"rowCount\":$(jv "$ROWS2" rowCount),\"quit\":$(jraw "$QUIT2"),\"rowsJson\":$(jraw "$ROWS2")}"
  add rowsJsonUnchangedByReload "$([ "$ROWS2" = "$ROWS_EDITED" ] && echo true || echo false)"
  add restartKeptData "$kept"
  add crashReports "${CRASHES:-0}"
  add_str vm "$VM"
  if [ "$(json_get "$STATE1" windowShown)" = true ] && [ "$(json_get "$ROWS1" rowCount)" = 5 ] && [ "$(json_get "$QUIT1" terminated)" = true ] \
     && [ "$(json_get "$EDIT" ok)" = true ] && [ "$(json_get "$STATE2" windowShown)" = true ] && [ "$(json_get "$QUIT2" terminated)" = true ] \
     && [ "$kept" = true ] && [ "${CRASHES:-0}" = 0 ]; then OK=true; else ERROR="journey checks failed: see the JSON fields"; fi
  ;;

*)
  die "usage: drive-mac.sh <selfcheck|build|launch|journey>"
  ;;
esac

emit_and_exit
