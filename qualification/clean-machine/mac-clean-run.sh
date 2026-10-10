#!/bin/bash
# mac-clean-run.sh - SR0 clean macOS package checks for SliceApp. Writes sr0-a.package-receipt/v2 run directories.
#
# Runs INSIDE a throw-away Tart guest (a clone of sliceapp-base), never on the host Mac. Profiles of one artifact;
# `qualification/run.py --stages package` takes the union of the run directories you pass it:
#   automated (default)  M00-M10, unattended
#   window-server        M11-window-visible only, unattended: the window server (CGWindowList) lists an on-screen window of
#                        the first launch. Not a screenshot: no pixels are inspected (see M11 below)
#   manual               M11-window-visible only: a recorded human/agent observation with screenshot evidence
# Give the runner exactly ONE M11 profile (window-server or manual): their evidence differs, so both would be a conflict.
# Each profile needs its own FRESH clone (a clean machine: no earlier install, data or launch in that guest).
#
#   bash mac-clean-run.sh --allowlist ~/clean-machine-allow.txt \
#     --old-dmg <path> --old-sha sha256:<64 hex> --old-version 0.1.0 \
#     --new-dmg <path> --new-sha sha256:<64 hex> --new-version 0.1.1 \
#     --node-bin <path> --right-release-cli <path> --interrupt-script <path> \
#     [--profile automated] [--receipts DIR] [--run-id ID] [--app-dir DIR] [--app-name SliceApp.app] [--bundle-id ID] \
#     [--allow-same-dmg]
#   bash mac-clean-run.sh --profile window-server --allowlist ~/clean-machine-allow.txt \
#     --old-dmg <path> --old-sha sha256:<64 hex> --old-version 0.1.0 --new-sha sha256:<64 hex> --new-version 0.1.1
#   bash mac-clean-run.sh --profile manual --allowlist ~/clean-machine-allow.txt \
#     --old-sha sha256:<64 hex> --new-sha sha256:<64 hex> --evidence <screenshot.png> --observer <name> --note <text>
#   bash mac-clean-run.sh --plan [--profile P]   # print the check order; touches nothing
#
# Rules this script enforces or follows:
#   * Refuses to run as root, as adrdsouza, as uid 501 unless the machine is a virtual machine (the Tart guest's admin
#     user is uid 501; the guest values are kern.hv_vmm_present=1 and hw.model=VirtualMac2,1), or unless id -un is
#     listed in the allow-list file. The allow-list must live under $HOME, be owned by the current user and not be
#     group/world writable. HOME must be /Users/<user>. The receipts directory must not exist yet or be empty.
#   * Every write stays under $HOME (test user). It never touches /Applications, /Library, or other users. It changes no
#     system setting: the guest is made offline (default routes removed) BEFORE the run by mac-vm-offline.sh, outside this script.
#   * No python3 and no xcrun: the vanilla guest has only the Command Line Tools shims, and each call pops an install
#     dialog. JSON is written with the system perl (JSON::PP). The notarization ticket is checked with
#     `syspolicy_check distribution` and spctl, not `xcrun stapler validate` (M03).
#   * The app is started by direct execution of its binary from the guest's SSH session. In the Tart guest that session
#     reaches the console session's window server: the window server (CGWindowList through osascript, VM only) must list an
#     on-screen window of the app process, else the launch FAILS (and an app that is not alive FAILS). open(1)
#     was tried and is not used: the installed copy inherits the DMG's quarantine, so LaunchServices shows the first-open
#     prompt and an unattended run cannot answer it (R7 final answered it over VNC; that path is not automated here).
#     Direct exec still makes Gatekeeper evaluate the quarantined app (syspolicyd "GK eval", counted per launch). Outside
#     a VM neither open nor osascript is used (workspace rule).
#   * M08 runs R7's interrupt method: scripts/interrupt-mac-install.sh with its hook against the REAL
#     `right-release install-app --recover` (host node binary and the pinned @rightkit/release copied into the guest),
#     modes copy, swap and swap-term, each recorded. It needs --node-bin, --right-release-cli and --interrupt-script.
#   * M11 cannot be a screenshot taken by the harness: screencapture is denied by TCC Screen Recording in the guest (tccd:
#     kTCCServiceScreenCapture does not allow prompting), and granting it is a system setting. Two honest options:
#     window-server (automated, weaker: the window server reports an on-screen layer-0 window of the app process, bounds and
#     alpha, dumped as evidence; it does not show that the window renders correctly) and manual (a screenshot someone took
#     and looked at; the harness hashes it, records who observed it and what they saw, and cannot inspect pixels).
#   * Each check writes <receipts>/<check_id>.json and the run writes <receipts>/run.json
#     (sr0-a.package-receipt/v2, schema: receipt.schema.json). A check passes only when its own observations pass.
#   * Requires the sealed build hashes (--old-sha/--new-sha). Without them the run refuses to start, so a wrong DMG
#     cannot produce a green run. Old and new must be two different builds (--allow-same-dmg is for a dry run: M06 FAILS).
set -u
set -o pipefail
export LC_ALL=C

SCRIPT_PATH="$0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_NAME="mac-clean-run.sh"
PLATFORM="mac"
# Profiles. qualification/run.py PACKAGE_CHECKS["macos-arm64"] must equal EXPECTED_AUTOMATED + EXPECTED_MANUAL, and
# EXPECTED_WINDOW must equal EXPECTED_MANUAL (both are ways to record M11; test_run.py HarnessDriftTests).
EXPECTED_AUTOMATED=(M00-environment M01-artifacts-bound M02-quarantined-delivery M03-gatekeeper-dmg \
                    M04-install-from-dmg M05-offline-first-launch M06-upgrade-dmg-replace \
                    M07-corrupt-binary-rejected M08-interrupted-install M09-rollback-readable \
                    M10-uninstall-keeps-data)
EXPECTED_MANUAL=(M11-window-visible)
EXPECTED_WINDOW=(M11-window-visible)

MAIN_USER="adrdsouza"
MAIN_UID=501

PROFILE="automated"
ALLOWLIST=""
OLD_DMG=""; OLD_SHA=""; OLD_VERSION=""
NEW_DMG=""; NEW_SHA=""; NEW_VERSION=""
RUN_ID=""
RECEIPTS=""
APP_DIR="$HOME/Applications"
APP_NAME="SliceApp.app"
BUNDLE_ID="dev.orthic.sliceapp"
DATA_DIR="$HOME/Library/Application Support/SliceApp"
NODE_BIN=""; RR_CLI=""; INTERRUPT_SCRIPT=""
EVIDENCE=""; OBSERVER=""; NOTE=""
ALLOW_SAME=0
PLAN_ONLY=0

die() { echo "mac-clean-run: $*" >&2; exit 2; }

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$SCRIPT_PATH"; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --allowlist) ALLOWLIST="$2"; shift 2 ;;
    --old-dmg) OLD_DMG="$2"; shift 2 ;;
    --old-sha) OLD_SHA="$2"; shift 2 ;;
    --old-version) OLD_VERSION="$2"; shift 2 ;;
    --new-dmg) NEW_DMG="$2"; shift 2 ;;
    --new-sha) NEW_SHA="$2"; shift 2 ;;
    --new-version) NEW_VERSION="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --receipts) RECEIPTS="$2"; shift 2 ;;
    --app-dir) APP_DIR="$2"; shift 2 ;;
    --app-name) APP_NAME="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    --node-bin) NODE_BIN="$2"; shift 2 ;;
    --right-release-cli) RR_CLI="$2"; shift 2 ;;
    --interrupt-script) INTERRUPT_SCRIPT="$2"; shift 2 ;;
    --evidence) EVIDENCE="$2"; shift 2 ;;
    --observer) OBSERVER="$2"; shift 2 ;;
    --note) NOTE="$2"; shift 2 ;;
    --allow-same-dmg) ALLOW_SAME=1; shift ;;
    --plan) PLAN_ONLY=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$PROFILE" in
  automated) EXPECTED=("${EXPECTED_AUTOMATED[@]}") ;;
  manual) EXPECTED=("${EXPECTED_MANUAL[@]}") ;;
  window-server) EXPECTED=("${EXPECTED_WINDOW[@]}") ;;
  *) die "--profile must be automated, window-server or manual" ;;
esac
[ -n "$RUN_ID" ] || RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$PROFILE"

if [ "$PLAN_ONLY" -eq 1 ]; then
  printf '%s\n' "${EXPECTED[@]}"
  exit 0
fi

# ---------------------------------------------------------------- identity guard (runs before anything else)
# A Virtualization.framework guest reports kern.hv_vmm_present=1 and hw.model=VirtualMac*; the host reports 0 and a Mac model.
in_vm() {
  [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" = 1 ] || return 1
  case "$(sysctl -n hw.model 2>/dev/null)" in VirtualMac*) return 0 ;; *) return 1 ;; esac
}

guard_identity() {
  local me uid
  me="$(id -un)"; uid="$(id -u)"
  [ "$uid" -ne 0 ] || die "refusing to run as root"
  [ "$me" != "$MAIN_USER" ] || die "refusing to run as $MAIN_USER (main workspace user)"
  [ "$uid" -ne "$MAIN_UID" ] || in_vm || die "refusing to run as uid $MAIN_UID outside a VM (main workspace user)"
  [ "$HOME" = "/Users/$me" ] || die "HOME ($HOME) is not /Users/$me"
  [ -n "$ALLOWLIST" ] || die "--allowlist is required (file created by the test user)"
  [ -f "$ALLOWLIST" ] || die "allow-list not found: $ALLOWLIST"
  case "$ALLOWLIST" in "$HOME"/*) ;; *) die "allow-list must live under $HOME" ;; esac
  [ -O "$ALLOWLIST" ] || die "allow-list must be owned by $me"
  [ -z "$(find "$ALLOWLIST" -perm -022 2>/dev/null)" ] || die "allow-list is group/world writable"
  # Strip comments and whitespace, then require the current user as an exact line and the main user absent.
  local listed
  listed="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ALLOWLIST" | grep -v '^$')"
  printf '%s\n' "$listed" | grep -Fxq "$me" || die "$me is not listed in $ALLOWLIST"
  printf '%s\n' "$listed" | grep -Fxq "$MAIN_USER" && die "$MAIN_USER must not appear in the allow-list"
  case "$APP_DIR" in "$HOME"/*) ;; *) die "--app-dir must be under $HOME" ;; esac
  case "$DATA_DIR" in "$HOME"/*) ;; *) die "--data-dir must be under $HOME" ;; esac
  if [ -n "$RECEIPTS" ]; then
    case "$RECEIPTS" in "$HOME"/*) ;; *) die "--receipts must be under $HOME" ;; esac
  fi
}

guard_identity
command -v perl >/dev/null 2>&1 && perl -MJSON::PP -e 1 2>/dev/null || die "perl with JSON::PP is required (the harness writes JSON with it; it never calls python3)"

SHA_RE='^sha256:[0-9a-f]{64}$'
printf '%s' "$OLD_SHA" | grep -Eq "$SHA_RE" || die "--old-sha must be sha256:<64 hex> from the sealed build"
printf '%s' "$NEW_SHA" | grep -Eq "$SHA_RE" || die "--new-sha must be sha256:<64 hex> from the sealed build"
SAME_DMG=0
if [ "$OLD_SHA" = "$NEW_SHA" ]; then
  [ "$ALLOW_SAME" -eq 1 ] || die "--old-sha equals --new-sha: a real run needs two different builds (--allow-same-dmg is for a dry run; M06 then FAILS)"
  SAME_DMG=1
fi

if [ "$PROFILE" = automated ]; then
  [ -n "$OLD_DMG" ] && [ -n "$NEW_DMG" ] || die "--old-dmg and --new-dmg are required"
  [ -n "$OLD_VERSION" ] && [ -n "$NEW_VERSION" ] || die "--old-version and --new-version are required"
  [ -f "$OLD_DMG" ] || die "old DMG not found: $OLD_DMG"
  [ -f "$NEW_DMG" ] || die "new DMG not found: $NEW_DMG"
  [ "$SAME_DMG" -eq 1 ] || [ "$OLD_VERSION" != "$NEW_VERSION" ] || die "--old-version equals --new-version: not an upgrade (--allow-same-dmg for a dry run)"
  case "$NODE_BIN$RR_CLI$INTERRUPT_SCRIPT" in *[[:space:]]*) die "--node-bin, --right-release-cli and --interrupt-script must not contain whitespace" ;; esac
elif [ "$PROFILE" = window-server ]; then
  [ -n "$OLD_DMG" ] && [ -f "$OLD_DMG" ] || die "--profile window-server needs --old-dmg (an existing file)"
  [ -n "$OLD_VERSION" ] || die "--profile window-server needs --old-version"
  [ -z "$NEW_DMG" ] || [ -f "$NEW_DMG" ] || die "new DMG not found: $NEW_DMG"
else
  [ -n "$EVIDENCE" ] || die "--profile manual needs --evidence <screenshot.png> taken by the observer"
  [ -n "$OBSERVER" ] || die "--profile manual needs --observer <name of the person or agent that looked at the window>"
  [ -n "$NOTE" ] || die "--profile manual needs --note <what was seen>"
  [ -f "$EVIDENCE" ] || die "evidence file not found: $EVIDENCE"
  [ -z "$OLD_DMG" ] || [ -f "$OLD_DMG" ] || die "old DMG not found: $OLD_DMG"
  [ -z "$NEW_DMG" ] || [ -f "$NEW_DMG" ] || die "new DMG not found: $NEW_DMG"
fi

[ -n "$RECEIPTS" ] || RECEIPTS="$HOME/clean-machine-receipts/$RUN_ID"
[ -z "$(ls -A "$RECEIPTS" 2>/dev/null)" ] || die "receipts directory is not empty: $RECEIPTS (one directory per profile run)"
WORK="$HOME/clean-machine-work/$RUN_ID"
mkdir -p "$RECEIPTS" "$WORK/logs" "$WORK/uninstalled" "$WORK/previous" "$HOME/Downloads" "$APP_DIR" || die "cannot create work dirs"

HARNESS_SHA="sha256:$(shasum -a 256 "$SCRIPT_PATH" | awk '{print $1}')"
RUN_START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ROWS="$DATA_DIR/rows.json"
if in_vm; then VM=true; else VM=false; fi
ENV_FILE="$WORK/env.tsv"
{
  printf 'host\t%s\n' "$(scutil --get ComputerName 2>/dev/null || hostname)"
  printf 'os_version\t%s %s (%s)\n' "macOS" "$(sw_vers -productVersion)" "$(sw_vers -buildVersion)"
  printf 'user\t%s\n' "$(id -un)"
  printf 'arch\t%s\n' "$(uname -m)"
  printf 'vm\t%s\n' "$VM"
  printf 'hw_model\t%s\n' "$(sysctl -n hw.model 2>/dev/null)"
  printf 'hv_vmm_present\t%s\n' "$(sysctl -n kern.hv_vmm_present 2>/dev/null)"
  printf 'profile\t%s\n' "$PROFILE"
} > "$ENV_FILE"

OBS_FILE=""; ART_FILE=""; CUR_ID=""; CUR_NAME=""; CUR_START=""
RUN_FAILS=0
APP_PID=""
OLD_DL=""; NEW_DL=""
MOUNTS=("")

# ---------------------------------------------------------------- check bookkeeping
check_begin() {
  CUR_ID="$1"; CUR_NAME="$2"
  CUR_START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  OBS_FILE="$WORK/obs-$CUR_ID.tsv"; ART_FILE="$WORK/art-$CUR_ID.tsv"
  : > "$OBS_FILE"; : > "$ART_FILE"
  echo "== $CUR_ID $CUR_NAME" >&2
}

obs() { printf '%s\t%s\n' "$1" "$(printf '%s' "$2" | tr '\t\n' '  ')" >> "$OBS_FILE"; }

art() {
  local name="$1" path="$2"
  if [ -f "$path" ]; then
    printf '%s\t%s\n' "$name" "sha256:$(shasum -a 256 "$path" | awk '{print $1}')" >> "$ART_FILE"
  fi
}

# check_finish <pass|fail> <implemented true|false> <rc or -> "<reason or ->"
check_finish() {
  local status="$1" impl="$2" rc="$3" reason="$4"
  [ "$status" = "pass" ] && [ "$impl" = "true" ] || RUN_FAILS=$((RUN_FAILS + 1))
  perl - "$RECEIPTS" "$RUN_ID" "$CUR_ID" "$CUR_NAME" "$impl" "$status" "$reason" "$rc" \
    "$CUR_START" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$OBS_FILE" "$ART_FILE" "$ENV_FILE" "$HARNESS_NAME" "$HARNESS_SHA" <<'PL'
use strict; use warnings; use JSON::PP;
my ($rdir, $run, $cid, $name, $impl, $status, $reason, $rc, $started, $ended,
    $obsf, $artf, $envf, $hname, $hsha) = @ARGV;
sub kv {
  my ($p) = @_; my %o;
  if (-e $p) {
    open(my $f, '<:encoding(UTF-8)', $p) or die "$p: $!";
    while (my $l = <$f>) { chomp $l; next unless $l =~ /\t/; my ($k, $v) = split(/\t/, $l, 2); $o{$k} = $v; }
    close $f;
  }
  return \%o;
}
my $implemented = $impl eq 'true';
if (!$implemented) { $status = 'fail'; $reason = 'not-implemented: ' . ($reason ne '-' ? $reason : 'no automated procedure'); }
my $why = $status eq 'pass' ? undef : ($reason ne '-' ? $reason : 'failed');
my %rec = (
  schema => 'sr0-a.package-receipt/v2', record => 'check', product => 'SliceApp', platform => 'macos-arm64',
  run_id => $run, check_id => $cid, check_name => $name,
  implemented => ($implemented ? JSON::PP::true : JSON::PP::false),
  status => $status, reason => $why, started_utc => $started, ended_utc => $ended,
  exit_status => ($rc eq '-' ? undef : 0 + $rc),
  observations => kv($obsf), artifact_ids => kv($artf), environment => kv($envf),
  harness => { name => $hname, sha256 => $hsha },
);
mkdir $rdir unless -d $rdir;
open(my $o, '>:raw', "$rdir/$cid.json") or die "$rdir/$cid.json: $!";
print $o JSON::PP->new->utf8->canonical->pretty->encode(\%rec);
close $o;
print STDERR "$cid: $status" . ($status eq 'pass' ? '' : " ($why)") . "\n";
PL
}

# ---------------------------------------------------------------- helpers
sha_of() { if [ -f "$1" ]; then shasum -a 256 "$1" | awk '{print "sha256:"$1}'; else echo missing; fi; }

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }

# Offline = no default route at all, v4 or v6, scoped or not (R7: netstat -rn lists none). mac-vm-offline.sh removes them.
default_routes() { netstat -rn 2>/dev/null | awk '$1=="default" {n++} END {print n+0}'; }
offline_now() { [ "$(default_routes)" -eq 0 ]; }
http_probe() { curl -s -m 5 -o /dev/null -w '%{http_code}' https://www.apple.com 2>/dev/null || true; }

# verify_bundle <app> <expected version>: the install gate. Returns 0 only if signature, Gatekeeper and identity agree.
verify_bundle() {
  local app="$1" want="$2" rc_cs rc_sp ver bid
  codesign --verify --deep --strict "$app" >"$WORK/logs/codesign-$CUR_ID.log" 2>&1; rc_cs=$?
  spctl --assess --type execute "$app" >"$WORK/logs/spctl-$CUR_ID.log" 2>&1; rc_sp=$?
  ver="$(plist "$app" CFBundleShortVersionString)"
  bid="$(plist "$app" CFBundleIdentifier)"
  obs "gate_codesign_rc" "$rc_cs"
  obs "gate_spctl_rc" "$rc_sp"
  obs "gate_version" "$ver"
  obs "gate_bundle_id" "$bid"
  [ "$rc_cs" -eq 0 ] && [ "$rc_sp" -eq 0 ] && [ "$ver" = "$want" ] && [ "$bid" = "$BUNDLE_ID" ]
}

# install_from_dmg <dmg> <expected version> <expected sha>: mount read-only, verify, then replace the app.
# Plain ditto (no --qtn): the copy carries no quarantine, so no first-open prompt blocks the launch.
install_from_dmg() {
  local dmg="$1" want="$2" want_sha="$3" mnt src dest prev
  [ "$(sha_of "$dmg")" = "$want_sha" ] || { obs "dmg_sha_mismatch" "1"; return 3; }
  mnt="$WORK/mnt-$CUR_ID-$RANDOM"; mkdir -p "$mnt"
  hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$dmg" >"$WORK/logs/attach-$CUR_ID.log" 2>&1 \
    || { obs "attach_failed" "1"; return 4; }
  MOUNTS+=("$mnt")
  src="$mnt/$APP_NAME"; dest="$APP_DIR/$APP_NAME"
  if ! verify_bundle "$src" "$want"; then
    hdiutil detach "$mnt" >/dev/null 2>&1; return 5
  fi
  if [ -e "$dest" ]; then
    prev="$WORK/previous/$CUR_ID-$RANDOM"; mkdir -p "$prev"
    mv "$dest" "$prev/" || { hdiutil detach "$mnt" >/dev/null 2>&1; return 6; }
    obs "previous_bundle_moved_to" "$prev"
  fi
  ditto "$src" "$dest" || { hdiutil detach "$mnt" >/dev/null 2>&1; return 7; }
  hdiutil detach "$mnt" >/dev/null 2>&1 || true
  verify_bundle "$dest" "$want"
}

installed_exe() {
  local e
  e="$(plist "$APP_DIR/$APP_NAME" CFBundleExecutable)"
  [ -n "$e" ] && printf '%s' "$APP_DIR/$APP_NAME/Contents/MacOS/$e"
}

app_pids() { local exe; exe="$(installed_exe)"; [ -n "$exe" ] && pgrep -f -- "$exe"; }

stop_app() {
  local pids i
  APP_PID=""
  pids="$(app_pids)" || return 0
  [ -n "$pids" ] || return 0
  kill -TERM $pids 2>/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    sleep 0.5
    app_pids >/dev/null 2>&1 || return 0
  done
  kill -KILL $pids 2>/dev/null
}

# What the window server reports for the app (VM only): sets WINDOWS to the number of on-screen windows of the process.
WINDOW_JS='ObjC.import("CoreGraphics"); ObjC.import("Foundation");
var pid = parseInt(ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey("PROBE_PID")));
var l = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, $.kCGNullWindowID)));
var m = l.filter(function(w) { return w.kCGWindowOwnerPID === pid && w.kCGWindowLayer === 0 && w.kCGWindowIsOnscreen === true; });
var area = 0, best = "none";
m.forEach(function(w) { var a = w.kCGWindowBounds.Width * w.kCGWindowBounds.Height; if (a > area) { area = a; best = w.kCGWindowBounds.Width + "x" + w.kCGWindowBounds.Height; } });
m.length + " " + best;'

# window_info <pid>: "<n> <WxH of the largest>" for the on-screen windows of the process, or "error". VM only.
window_info() {
  PROBE_PID="$1" /usr/bin/osascript -l JavaScript -e "$WINDOW_JS" 2>/dev/null || echo error
}

# Gatekeeper's verdict on the launch, from syspolicyd (counted since the launch; the lines are kept as an artifact).
gk_eval() { # <since> <label>
  local out
  out="$(/usr/bin/log show --start "$1" --info --predicate 'process == "syspolicyd" AND eventMessage CONTAINS "GK eval"' 2>/dev/null | grep 'GK eval')"
  printf '%s\n' "$out" > "$WORK/logs/gk-eval-$CUR_ID-$2.log"
  obs "gk_eval_allowed_$2" "$(printf '%s\n' "$out" | grep -c 'was allowed: 1')"
  obs "gk_eval_denied_$2" "$(printf '%s\n' "$out" | grep -c 'was allowed: 0')"
}

LAUNCH_TIMEOUT=60   # an offline first exec of a quarantined app waits on syspolicyd's CloudKit lookup (about 18 s in R8 dry runs)

# launch_app <label>: direct exec of the installed binary. In a VM it returns 0 only if the window server lists an on-screen
# window of the process within LAUNCH_TIMEOUT s (the time is recorded) and the process is still alive 5 s later; outside a
# VM only if the process is alive 15 s after the launch.
launch_app() {
  local label="$1" exe since waited=0 info="error" n
  exe="$(installed_exe)"
  [ -n "$exe" ] || { obs "launch_${label}_alive" "false"; return 1; }
  stop_app
  since="$(date '+%Y-%m-%d %H:%M:%S')"
  "$exe" >"$WORK/logs/app-$CUR_ID-$label.log" 2>&1 &
  disown $! 2>/dev/null   # no "Terminated" job message when stop_app ends it
  obs "launch_${label}_method" "direct exec of the binary from the guest SSH session (quarantined copy, Gatekeeper evaluates the exec; no first-open prompt)"
  APP_PID=""
  if in_vm; then
    while [ "$waited" -lt "$LAUNCH_TIMEOUT" ]; do
      sleep 1; waited=$((waited + 1))
      APP_PID="$(app_pids | head -1)"
      if [ -z "$APP_PID" ]; then [ "$waited" -ge 3 ] && break; continue; fi
      info="$(window_info "$APP_PID")"; n="${info%% *}"
      case "$n" in ''|*[!0-9]*) ;; *) [ "$n" -ge 1 ] && break ;; esac
    done
    if [ -n "$APP_PID" ]; then sleep 5; info="$(window_info "$APP_PID")"; fi
    obs "launch_${label}_seconds_to_window" "$waited"
    obs "window_server_${label}" "on-screen windows of the app process: ${info%% *}, largest ${info#* } (window server, via osascript CGWindowList)"
  else
    sleep 15
    APP_PID="$(app_pids | head -1)"
    obs "window_server_${label}" "skipped (not a VM)"
  fi
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    obs "launch_${label}_alive" "true"
    gk_eval "$since" "$label"
    if in_vm; then
      n="${info%% *}"
      case "$n" in ''|*[!0-9]*) obs "launch_${label}_window" "none"; return 1 ;; esac
      [ "$n" -ge 1 ] || { obs "launch_${label}_window" "none"; return 1; }
    fi
    return 0
  fi
  APP_PID=""
  obs "launch_${label}_alive" "false"; return 1
}

# deliver_dmg <tag> <src> <seal sha>: copy to ~/Downloads and set the quarantine attribute a browser download would set.
# Sets DELIVERED; returns 0 if the copy equals the seal and carries a quarantine attribute.
deliver_dmg() {
  local tag="$1" src="$2" want="$3" dl q ok=0
  dl="$HOME/Downloads/SliceApp-$tag-$RUN_ID.dmg"; DELIVERED="$dl"
  cp "$src" "$dl" || ok=1
  chmod u+w "$dl" 2>/dev/null   # a sealed DMG is mode 0444; xattr -w needs write permission
  [ "$(sha_of "$dl")" = "$want" ] || { ok=1; obs "copy_hash_mismatch_${tag}" "1"; }
  # flags 0081 (downloaded, quarantined), hex time, agent name, UUID
  xattr -w com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)" "$dl" 2>/dev/null || ok=1
  q="$(xattr -p com.apple.quarantine "$dl" 2>/dev/null)"
  obs "quarantine_${tag}" "${q:-missing}"
  [ -n "$q" ] || ok=1
  return $ok
}

# window_dump <pid> <file>: the raw window-server entries (CGWindowList, all windows) of the process, as JSON.
WINDOW_DUMP_JS='ObjC.import("CoreGraphics"); ObjC.import("Foundation");
var pid = parseInt(ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey("PROBE_PID")));
var l = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, $.kCGNullWindowID)));
JSON.stringify(l.filter(function(w) { return w.kCGWindowOwnerPID === pid; }), null, 1);'
window_dump() { PROBE_PID="$1" /usr/bin/osascript -l JavaScript -e "$WINDOW_DUMP_JS" > "$2" 2>/dev/null; }

rows_schema_ok() {
  perl -MJSON::PP -e '
    my ($path, $want) = @ARGV;
    open(my $f, "<:raw", $path) or do { print STDERR "unreadable: $!\n"; exit 1 };
    local $/; my $doc = eval { decode_json(<$f>) };
    if (!defined $doc) { print STDERR "unparseable: $@\n"; exit 1 }
    exit((ref($doc) eq "HASH" && defined $doc->{schema} && $doc->{schema} eq $want) ? 0 : 1);
  ' "$1" "$2"
}

cleanup() {
  stop_app
  for m in "${MOUNTS[@]:-}"; do
    [ -n "$m" ] && hdiutil detach "$m" >/dev/null 2>&1
  done
}
trap cleanup EXIT

write_run_record() {
  perl - "$RECEIPTS" "$RUN_ID" "$RUN_START" "$HARNESS_NAME" "$HARNESS_SHA" "$OLD_SHA" "$NEW_SHA" "${EXPECTED[@]}" <<'PL'
use strict; use warnings; use JSON::PP;
my ($rdir, $run, $started, $hname, $hsha, $old_sha, $new_sha, @expected) = @ARGV;
opendir(my $d, $rdir) or die "$rdir: $!";
my @files = sort grep { /^M\d\d-[a-z0-9-]+\.json$/ } readdir $d;
closedir $d;
my %by_id;
for my $name (@files) {
  open(my $f, '<:raw', "$rdir/$name") or die "$rdir/$name: $!";
  local $/; my $rec = decode_json(<$f>); close $f;
  $by_id{$rec->{check_id}} = $rec if ref $rec eq 'HASH' && ($rec->{record} // '') eq 'check';
}
my (@checks, @missing, @not_ok);
for my $id (@expected) {
  my $rec = $by_id{$id};
  if (!$rec) { push @missing, $id; push @checks, { check_id => $id, status => 'fail', implemented => JSON::PP::false }; next; }
  push @checks, { check_id => $id, status => $rec->{status}, implemented => $rec->{implemented} };
  push @not_ok, $id if $rec->{status} ne 'pass' || !$rec->{implemented};
}
my $ok = !@missing && !@not_ok;
my $reason = $ok ? undef : (@missing ? 'missing receipts: ' . join(', ', @missing) : 'checks not passing: ' . join(', ', @not_ok));
my @t = gmtime(); my $now = sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $t[5] + 1900, $t[4] + 1, @t[3, 2, 1, 0]);
my %rec = (
  schema => 'sr0-a.package-receipt/v2', record => 'run', product => 'SliceApp', platform => 'macos-arm64',
  run_id => $run, status => ($ok ? 'pass' : 'fail'), expected_checks => \@expected, checks => \@checks,
  started_utc => $started, ended_utc => $now, reason => $reason,
  artifact_ids => { old_dmg => $old_sha, new_dmg => $new_sha },
  harness => { name => $hname, sha256 => $hsha },
);
open(my $o, '>:raw', "$rdir/run.json") or die "$rdir/run.json: $!";
print $o JSON::PP->new->utf8->canonical->pretty->encode(\%rec);
close $o;
print STDERR "run $run: " . $rec{status} . ($ok ? '' : " ($reason)") . "\n";
exit($ok ? 0 : 1);
PL
}

echo "clean-machine run $RUN_ID (mac, profile $PROFILE, vm=$VM) receipts: $RECEIPTS" >&2

# ================================================================ profile window-server: M11 (unattended)
if [ "$PROFILE" = window-server ]; then
  # M11 from the window server, not from pixels: install the old build from its quarantined DMG on a clean machine, launch it
  # (first launch), and require that CGWindowList lists an on-screen, visible (alpha > 0) layer-0 window of at least 200x100
  # for the app process while it is alive. The raw window list is the evidence artifact. This does NOT show the window renders
  # correctly; the manual profile (a screenshot someone looked at) is the stronger record.
  check_begin M11-window-visible "Window visible on first launch (window server, unattended)"
  w_ok=1; w_why=""
  if ! in_vm; then
    w_ok=0; w_why="the window server probe runs only in a VM guest"
  elif [ -e "$ROWS" ]; then
    obs "rows_json_before_launch" "present"; w_ok=0; w_why="rows.json already existed: not a first launch on a clean machine"
  elif [ -n "$NEW_DMG" ] && [ "$(sha_of "$NEW_DMG")" != "$NEW_SHA" ]; then
    w_ok=0; w_why="new DMG does not match --new-sha"
  elif ! deliver_dmg OLD "$OLD_DMG" "$OLD_SHA"; then
    w_ok=0; w_why="old DMG copy differs from the seal or has no quarantine attribute"
  else
    OLD_DL="$DELIVERED"
    install_from_dmg "$OLD_DL" "$OLD_VERSION" "$OLD_SHA"; rc_in=$?
    obs "install_rc" "$rc_in"
    if [ "$rc_in" -ne 0 ]; then
      w_ok=0; w_why="install_from_dmg rc=$rc_in"
    elif launch_app first; then
      dump="$RECEIPTS/M11-window-visible.windows.json"
      window_dump "$APP_PID" "$dump"
      seen="$(perl -MJSON::PP -e '
        local $/; my $d = eval { decode_json(<STDIN>) } || [];
        my ($best, $bw, $bh) = (0, 0, 0);
        for my $w (@$d) {
          next unless $w->{kCGWindowLayer} == 0 && $w->{kCGWindowIsOnscreen} && ($w->{kCGWindowAlpha} // 0) > 0;
          my ($x, $y) = ($w->{kCGWindowBounds}{Width}, $w->{kCGWindowBounds}{Height});
          if ($x >= 200 && $y >= 100 && $x * $y > $best) { ($best, $bw, $bh) = ($x * $y, $x, $y); }
        }
        print $best ? "${bw}x${bh}" : "none";' < "$dump" 2>/dev/null)"
      obs "visible_window_largest" "${seen:-none}"
      if [ -z "$seen" ] || [ "$seen" = none ]; then
        w_ok=0; w_why="no on-screen visible layer-0 window of at least 200x100 in the window server dump"
      else
        art evidence "$dump"
        obs "observer" "harness"
        obs "method" "window server (CGWindowList through osascript in the guest console session) lists an on-screen, visible layer-0 window of the app process; raw entries in M11-window-visible.windows.json; no pixels inspected, no screenshot (screencapture is denied by TCC Screen Recording)"
      fi
    else
      w_ok=0; w_why="first launch failed: app not alive, or the window server listed no on-screen window"
    fi
    stop_app
  fi
  if [ "$w_ok" -eq 1 ]; then check_finish pass true - -; else check_finish fail true - "$w_why"; fi
  write_run_record; run_rc=$?
  [ "$RUN_FAILS" -eq 0 ] && [ "$run_rc" -eq 0 ] || exit 1
  exit 0
fi

# ================================================================ profile manual: M11
if [ "$PROFILE" = manual ]; then
  # M11: a recorded human observation. The harness cannot look at pixels and does not claim to: it binds the screenshot
  # by hash, records who observed it and what they said they saw, and refuses a missing, non-PNG or unattributed record.
  check_begin M11-window-visible "Window visible on first launch (recorded human observation)"
  m11_ok=1; m11_why=""
  [ -z "$OLD_DMG" ] || [ "$(sha_of "$OLD_DMG")" = "$OLD_SHA" ] || { m11_ok=0; m11_why="old DMG does not match --old-sha"; }
  [ -z "$NEW_DMG" ] || [ "$(sha_of "$NEW_DMG")" = "$NEW_SHA" ] || { m11_ok=0; m11_why="new DMG does not match --new-sha"; }
  magic="$(head -c 8 "$EVIDENCE" | od -An -tx1 | tr -d ' \n')"
  if [ "$magic" != 89504e470d0a1a0a ]; then m11_ok=0; m11_why="evidence is not a PNG file"; fi
  case "$OBSERVER" in harness|Harness|HARNESS) m11_ok=0; m11_why="observer harness is reserved for automated evidence; name the person or agent that looked" ;; esac
  if [ "$m11_ok" -eq 1 ]; then
    cp "$EVIDENCE" "$RECEIPTS/M11-window-visible.png"
    art evidence "$RECEIPTS/M11-window-visible.png"
    obs "manual" "true"
    obs "observer" "$OBSERVER"
    obs "method" "screenshot of the guest console display taken by the observer; the harness hashes it and does not inspect pixels"
    obs "note" "$NOTE"
    obs "evidence_file" "M11-window-visible.png"
    check_finish pass true - -
  else
    check_finish fail true - "$m11_why"
  fi
  write_run_record; run_rc=$?
  [ "$RUN_FAILS" -eq 0 ] && [ "$run_rc" -eq 0 ] || exit 1
  exit 0
fi

# ================================================================ profile automated: M00-M10
# M00: environment and offline precondition
check_begin M00-environment "Environment and offline precondition"
obs "user" "$(id -un)"; obs "arch" "$(uname -m)"; obs "os" "$(sw_vers -productVersion)"
obs "allowlist" "$ALLOWLIST"; obs "vm" "$VM"
obs "hw_model" "$(sysctl -n hw.model 2>/dev/null)"; obs "hv_vmm_present" "$(sysctl -n kern.hv_vmm_present 2>/dev/null)"
n_routes="$(default_routes)"; obs "default_routes" "$n_routes"
probe_code="$(http_probe)"; obs "apple_probe_http_code" "${probe_code:-none}"
if [ -e "$ROWS" ]; then obs "data_dir_preexisting" "true"; else obs "data_dir_preexisting" "false"; fi
if [ "$(uname -m)" = "arm64" ] && [ "$n_routes" -eq 0 ] && [ "${probe_code:-000}" = "000" ]; then
  check_finish pass true - -
else
  check_finish fail true - "arch must be arm64, no default route (v4 or v6) and https://www.apple.com unreachable (run mac-vm-offline.sh in the guest first)"
fi

# M01: artifacts bound to the sealed hashes
check_begin M01-artifacts-bound "Input DMGs match the sealed build hashes"
art old_dmg "$OLD_DMG"; art new_dmg "$NEW_DMG"
obs "old_version" "$OLD_VERSION"; obs "new_version" "$NEW_VERSION"
[ "$SAME_DMG" -eq 1 ] && obs "same_dmg_dry_run" "true"
if [ "$(sha_of "$OLD_DMG")" = "$OLD_SHA" ] && [ "$(sha_of "$NEW_DMG")" = "$NEW_SHA" ]; then
  check_finish pass true - -
else
  check_finish fail true - "DMG hash does not match --old-sha/--new-sha"
fi

# M02: quarantined delivery (download simulation). Copies go to the test user's Downloads.
check_begin M02-quarantined-delivery "Quarantined delivery of both DMGs"
q_ok=1
for tag in OLD NEW; do
  if [ "$tag" = OLD ]; then src="$OLD_DMG"; want="$OLD_SHA"; else src="$NEW_DMG"; want="$NEW_SHA"; fi
  deliver_dmg "$tag" "$src" "$want" || q_ok=0
  if [ "$tag" = "OLD" ]; then OLD_DL="$DELIVERED"; else NEW_DL="$DELIVERED"; fi
done
if [ "$q_ok" -eq 1 ]; then check_finish pass true - -; else check_finish fail true - "quarantine attribute missing on a copy or a copy differs from the seal"; fi

# M03: Gatekeeper assessment and the notarization ticket, for each quarantined DMG and the .app inside it.
#   spctl source=Notarized Developer ID  proves Gatekeeper accepts the artifact as notarized (ticket or online lookup).
#   syspolicy_check distribution          proves the ticket is physically stapled to the artifact (a missing staple is the
#                                         fatal "Notary Ticket Missing", the offline-first-launch precondition) plus the
#                                         signature and hardened-runtime pre-distribution checks.
# This replaces `xcrun stapler validate` (the vanilla guest has no Xcode tools). It does not prove a copy of the .app
# delivered without its DMG; M05 observes the real offline first launch.
check_begin M03-gatekeeper-dmg "Gatekeeper and stapled notarization ticket of the quarantined DMGs and their apps"
m03_ok=1; m03_why=""
for tag in old new; do
  if [ "$tag" = old ]; then dl="$OLD_DL"; else dl="$NEW_DL"; fi
  spctl --assess --type open --context context:primary-signature -vv "$dl" >"$WORK/logs/gk-open-$tag.log" 2>&1; rc_gk=$?
  src_gk="$(sed -n 's/^source=//p' "$WORK/logs/gk-open-$tag.log" | head -1)"
  syspolicy_check distribution "$dl" >"$WORK/logs/syspolicy-dmg-$tag.log" 2>&1; rc_sd=$?
  obs "${tag}_dmg_spctl_rc" "$rc_gk"; obs "${tag}_dmg_spctl_source" "${src_gk:-none}"; obs "${tag}_dmg_syspolicy_rc" "$rc_sd"
  [ "$rc_gk" -eq 0 ] && [ "$src_gk" = "Notarized Developer ID" ] || { m03_ok=0; m03_why="$m03_why $tag DMG spctl rc=$rc_gk source=${src_gk:-none};"; }
  [ "$rc_sd" -eq 0 ] || { m03_ok=0; m03_why="$m03_why $tag DMG syspolicy_check rc=$rc_sd;"; }
  mnt="$WORK/mnt-m03-$tag"; mkdir -p "$mnt"
  if hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$dl" >"$WORK/logs/attach-m03-$tag.log" 2>&1; then
    MOUNTS+=("$mnt")
    spctl --assess --type execute -vv "$mnt/$APP_NAME" >"$WORK/logs/gk-exec-$tag.log" 2>&1; rc_ga=$?
    src_ga="$(sed -n 's/^source=//p' "$WORK/logs/gk-exec-$tag.log" | head -1)"
    syspolicy_check distribution "$mnt/$APP_NAME" >"$WORK/logs/syspolicy-app-$tag.log" 2>&1; rc_sa=$?
    hdiutil detach "$mnt" >/dev/null 2>&1
    obs "${tag}_app_spctl_rc" "$rc_ga"; obs "${tag}_app_spctl_source" "${src_ga:-none}"; obs "${tag}_app_syspolicy_rc" "$rc_sa"
    [ "$rc_ga" -eq 0 ] && [ "$src_ga" = "Notarized Developer ID" ] || { m03_ok=0; m03_why="$m03_why $tag app spctl rc=$rc_ga source=${src_ga:-none};"; }
    [ "$rc_sa" -eq 0 ] || { m03_ok=0; m03_why="$m03_why $tag app syspolicy_check rc=$rc_sa (ticket not stapled to the app?);"; }
  else
    obs "${tag}_attach_failed" "1"; m03_ok=0; m03_why="$m03_why $tag DMG did not mount;"
  fi
done
if [ "$m03_ok" -eq 1 ]; then check_finish pass true 0 -; else check_finish fail true 1 "$m03_why"; fi

# M04: install the old build from its DMG (verify first, then copy)
check_begin M04-install-from-dmg "Install old build from DMG (verify before copy)"
install_from_dmg "$OLD_DL" "$OLD_VERSION" "$OLD_SHA"; rc_in=$?
art installed_binary "$(installed_exe)"
obs "install_rc" "$rc_in"
if [ "$rc_in" -eq 0 ]; then check_finish pass true "$rc_in" -; else check_finish fail true "$rc_in" "install_from_dmg rc=$rc_in"; fi

# M05: offline first launch; data file must be created at the declared path (and must not exist before: a clean machine)
check_begin M05-offline-first-launch "Offline first launch writes rows.json"
if [ -e "$ROWS" ]; then
  obs "rows_json_before_launch" "present"
  check_finish fail true - "rows.json already existed before the first launch: not a clean machine"
elif offline_now; then
  if launch_app first; then
    stop_app
    if [ -f "$ROWS" ] && rows_schema_ok "$ROWS" 1; then
      art rows_json_after_first_launch "$ROWS"; obs "rows_json" "present, schema 1"
      check_finish pass true - -
    else
      check_finish fail true - "rows.json missing or not schema 1 at $ROWS"
    fi
  else
    stop_app
    check_finish fail true - "app not alive, or (VM) the window server listed no on-screen window for it within 60 s"
  fi
else
  check_finish fail true - "network is online; offline precondition not met"
fi

# M06: upgrade by DMG replace; rows.json unchanged by the install. Needs two different builds.
check_begin M06-upgrade-dmg-replace "Upgrade by DMG replace keeps rows.json"
stop_app
pre_sha="$(sha_of "$ROWS" 2>/dev/null || echo missing)"
obs "rows_sha_before" "$pre_sha"; obs "old_version" "$OLD_VERSION"; obs "new_version" "$NEW_VERSION"
install_from_dmg "$NEW_DL" "$NEW_VERSION" "$NEW_SHA"; rc_up=$?
obs "install_rc" "$rc_up"
post_sha="$(sha_of "$ROWS" 2>/dev/null || echo missing)"
obs "rows_sha_after_install" "$post_sha"
if [ "$SAME_DMG" -eq 1 ]; then
  obs "same_dmg_dry_run" "true"
  check_finish fail true "$rc_up" "same-dmg dry run: old and new are the same build, so this is not an upgrade"
elif [ "$rc_up" -eq 0 ] && [ "$pre_sha" = "$post_sha" ] && [ "$pre_sha" != missing ] && launch_app upgraded; then
  stop_app
  check_finish pass true "$rc_up" -
else
  stop_app
  check_finish fail true "$rc_up" "upgrade rc=$rc_up rows before=$pre_sha after=$post_sha"
fi

# M07: corrupt binary must be refused by the gate and must not replace the installed bundle
check_begin M07-corrupt-binary-rejected "Corrupt binary rejected by the install gate"
CORRUPT="$WORK/corrupt/$APP_NAME"; mkdir -p "$WORK/corrupt"; rm -rf "$CORRUPT"
ditto "$APP_DIR/$APP_NAME" "$CORRUPT"
EXEC_NAME="$(plist "$CORRUPT" CFBundleExecutable)"
installed_before="$(sha_of "$APP_DIR/$APP_NAME/Contents/MacOS/$EXEC_NAME")"
flip_info="$(perl -e '
  my $p = shift;
  open(my $f, "+<:raw", $p) or die "$p: $!";
  local $/; my $b = <$f>;
  my $off = int(length($b) / 2); my $before = ord(substr($b, $off, 1));
  substr($b, $off, 1) = chr($before ^ 1);
  seek($f, 0, 0); print $f $b; truncate($f, length($b)); close $f;
  printf("%d\t%02x\t%02x\n", $off, $before, $before ^ 1);
' "$CORRUPT/Contents/MacOS/$EXEC_NAME")"
obs "flipped_offset_before_after" "$flip_info"
verify_bundle "$CORRUPT" "$NEW_VERSION"; gate_rc=$?
installed_after="$(sha_of "$APP_DIR/$APP_NAME/Contents/MacOS/$EXEC_NAME")"
obs "gate_rc_on_corrupt" "$gate_rc"
obs "installed_binary_sha_before" "$installed_before"
obs "installed_binary_sha_after" "$installed_after"
if [ -n "$flip_info" ] && [ "$gate_rc" -ne 0 ] && [ "$installed_before" = "$installed_after" ]; then
  check_finish pass true "$gate_rc" -
else
  check_finish fail true "$gate_rc" "gate accepted corrupt bundle, no byte was flipped, or installed bundle changed"
fi

# M08: interrupted install, R7's method: interrupt-mac-install.sh + hook against the REAL right-release install-app
# (the pinned @rightkit/release and the host's node binary copied into the guest), into a scratch destination under
# $WORK, never into $APP_DIR. Modes: copy (SIGKILL while ditto copies into staging), swap (SIGKILL between the two swap
# renames), swap-term (SIGTERM at the same point; the signal handler must roll back). Each mode: install old, launch,
# interrupt the upgrade to new, check, `install-app --recover`, check, uninterrupted install. Exit 0 of the script =
# every expectation held; 3 = the interruption did not fire (recorded as a failure).
check_begin M08-interrupted-install "Interrupted install at copy/swap boundaries (real right-release install-app --recover)"
stop_app
m08_ok=1; m08_why=""
if [ -z "$NODE_BIN" ] || [ -z "$RR_CLI" ] || [ -z "$INTERRUPT_SCRIPT" ]; then
  check_finish fail true - "--node-bin, --right-release-cli and --interrupt-script are required for M08"
elif [ ! -x "$NODE_BIN" ] || [ ! -f "$RR_CLI" ] || [ ! -f "$INTERRUPT_SCRIPT" ] || [ ! -f "$(dirname "$INTERRUPT_SCRIPT")/interrupt-mac-install-hook.mjs" ]; then
  check_finish fail true - "node binary, right-release CLI, interrupt script or its hook not found"
elif [ "$(sha_of "$OLD_DL")" != "$OLD_SHA" ] || [ "$(sha_of "$NEW_DL")" != "$NEW_SHA" ]; then
  check_finish fail true - "delivered DMG copies no longer match the seal"
else
  art node_bin "$NODE_BIN"; art right_release_cli "$RR_CLI"
  art interrupt_script "$INTERRUPT_SCRIPT"; art interrupt_hook "$(dirname "$INTERRUPT_SCRIPT")/interrupt-mac-install-hook.mjs"
  obs "node_version" "$("$NODE_BIN" --version 2>&1 | head -1)"
  rr_pkg="$(dirname "$RR_CLI")/../package.json"
  obs "right_release_version" "$(perl -MJSON::PP -e 'open(my $f, "<", shift) or exit; local $/; my $d = eval { decode_json(<$f>) }; print $d->{version} // "unknown"' "$rr_pkg" 2>/dev/null)"
  for mode in copy swap swap-term; do
    key="${mode//-/_}"; log="$WORK/logs/m08-$mode.log"; mkdir -p "$WORK/tmp-m08-$mode"
    ( cd "$WORK" && TMPDIR="$WORK/tmp-m08-$mode" SLICEAPP_DATA_DIR="$DATA_DIR" SLICEAPP_LAUNCH=1 RIGHT_RELEASE="$NODE_BIN $RR_CLI" \
        sh "$INTERRUPT_SCRIPT" --old-dmg "$OLD_DL" --new-dmg "$NEW_DL" --mode "$mode" ) >"$log" 2>&1
    rc_m=$?
    n_pass="$(grep -c '^EXPECT PASS' "$log")"; n_fail="$(grep -c '^EXPECT FAIL' "$log")"
    if grep -q '^hook: .*"fired":true' "$log"; then fired=true; else fired=false; fi
    obs "${key}_rc" "$rc_m"; obs "${key}_hook_fired" "$fired"
    obs "${key}_expect_pass" "$n_pass"; obs "${key}_expect_fail" "$n_fail"
    obs "${key}_post_interrupt" "$(grep -E '^\[post-interrupt\] app ' "$log" | head -1)"
    obs "${key}_after_recover" "$(grep -E '^OBSERVED: after --recover' "$log" | head -1)"
    art "m08_log_$key" "$log"
    if [ "$rc_m" -ne 0 ] || [ "$n_fail" -ne 0 ] || [ "$n_pass" -eq 0 ] || [ "$fired" != true ]; then
      m08_ok=0; m08_why="$m08_why $mode (rc=$rc_m, expect fail=$n_fail, hook fired=$fired);"
    fi
  done
  if [ "$m08_ok" -eq 1 ]; then check_finish pass true 0 -; else check_finish fail true 1 "interrupted install mode(s) failed:$m08_why"; fi
fi

# M09: rollback readability (old build reads data written by new build)
check_begin M09-rollback-readable "Old build reads data written by new build"
stop_app
pre_sha="$(sha_of "$ROWS" 2>/dev/null || echo missing)"
obs "rows_sha_before_rollback" "$pre_sha"
install_from_dmg "$OLD_DL" "$OLD_VERSION" "$OLD_SHA"; rc_rb=$?
obs "install_rc" "$rc_rb"
if [ "$rc_rb" -eq 0 ] && launch_app rollback; then
  stop_app
  if rows_schema_ok "$ROWS" 1; then
    obs "rows_readable_by_old" "true"
    check_finish pass true "$rc_rb" -
  else
    obs "rows_readable_by_old" "false"
    check_finish fail true "$rc_rb" "rows.json not schema 1 after old launch"
  fi
else
  stop_app
  check_finish fail true "$rc_rb" "rollback install rc=$rc_rb or old build not alive / no window"
fi

# M10: uninstall keeps user data. The bundle is moved to a scratch folder (not the Trash).
check_begin M10-uninstall-keeps-data "Uninstall keeps rows.json"
stop_app
pre_sha="$(sha_of "$ROWS" 2>/dev/null || echo missing)"
mv "$APP_DIR/$APP_NAME" "$WORK/uninstalled/" 2>/dev/null; rc_un=$?
post_sha="$(sha_of "$ROWS" 2>/dev/null || echo missing)"
obs "rows_sha_before" "$pre_sha"; obs "rows_sha_after" "$post_sha"; obs "bundle_removed_rc" "$rc_un"
if [ "$rc_un" -eq 0 ] && [ ! -e "$APP_DIR/$APP_NAME" ] && [ "$pre_sha" = "$post_sha" ] && [ "$pre_sha" != missing ]; then
  check_finish pass true "$rc_un" -
else
  check_finish fail true "$rc_un" "uninstall did not keep rows.json (before=$pre_sha after=$post_sha)"
fi

# ---------------------------------------------------------------- run summary
write_run_record; run_rc=$?
[ "$RUN_FAILS" -eq 0 ] && [ "$run_rc" -eq 0 ] || exit 1
exit 0
