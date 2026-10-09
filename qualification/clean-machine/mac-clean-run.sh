#!/bin/bash
# mac-clean-run.sh - SR0 R7 clean macOS checks for SliceApp (prep; not yet run).
#
# Run as the dedicated test user (never Adrian's account), from that user's own login session:
#   bash mac-clean-run.sh --allowlist ~/clean-machine-allow.txt \
#     --old-dmg <path> --old-sha sha256:<hex> --old-version 0.1.0 \
#     --new-dmg <path> --new-sha sha256:<hex> --new-version 0.1.1 \
#     [--receipts DIR] [--run-id ID] [--app-dir DIR] [--app-name SliceApp.app] [--bundle-id ID]
#   bash mac-clean-run.sh --plan        # print the check order; touches nothing
#
# Rules this script enforces or follows:
#   * Refuses to run as root, as adrdsouza, as uid 501, or unless id -un is listed in the allow-list file.
#     The allow-list must live under $HOME, be owned by the current user, and not be group/world writable.
#   * Every write stays under $HOME (test user). It never touches /Applications, /Library, or other users.
#   * Never runs open, osascript, screencapture, or notifyutil -p (workspace rule). The app is started by
#     direct execution of its binary. The Finder/Gatekeeper first-launch dialog is a manual step in
#     mac-clean-checklist.md; the window check (M11) is not automated and FAILS until observed.
#   * Each check writes <receipts>/<check_id>.json (schema: ../receipt.schema.json). A check passes only
#     when its own observations pass. Unimplemented checks are recorded as fail (not-implemented).
#   * Requires the sealed build hashes (--old-sha/--new-sha). Without them the run refuses to start,
#     so a wrong DMG cannot produce a green run.
set -u
set -o pipefail
export LC_ALL=C

SCRIPT_PATH="$0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_NAME="mac-clean-run.sh"
PLATFORM="mac"
EXPECTED=(M00-environment M01-artifacts-bound M02-quarantined-delivery M03-gatekeeper-dmg \
          M04-install-from-dmg M05-offline-first-launch M06-upgrade-dmg-replace \
          M07-corrupt-binary-rejected M08-interrupted-install M09-rollback-readable \
          M10-uninstall-keeps-data M11-window-visible)

MAIN_USER="adrdsouza"
MAIN_UID=501

ALLOWLIST=""
OLD_DMG=""; OLD_SHA=""; OLD_VERSION=""
NEW_DMG=""; NEW_SHA=""; NEW_VERSION=""
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RECEIPTS=""
APP_DIR="$HOME/Applications"
APP_NAME="SliceApp.app"
BUNDLE_ID="dev.orthic.sliceapp"
DATA_DIR="$HOME/Library/Application Support/SliceApp"
PLAN_ONLY=0

die() { echo "mac-clean-run: $*" >&2; exit 2; }

usage() { sed -n '2,20p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
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
    --plan) PLAN_ONLY=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [ "$PLAN_ONLY" -eq 1 ]; then
  printf '%s\n' "${EXPECTED[@]}"
  exit 0
fi

# ---------------------------------------------------------------- identity guard (runs before anything else)
guard_identity() {
  local me uid
  me="$(id -un)"; uid="$(id -u)"
  [ "$uid" -ne 0 ] || die "refusing to run as root"
  [ "$me" != "$MAIN_USER" ] || die "refusing to run as $MAIN_USER (main workspace user)"
  [ "$uid" -ne "$MAIN_UID" ] || die "refusing to run as uid $MAIN_UID (main workspace user)"
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
[ -n "$OLD_DMG" ] && [ -n "$NEW_DMG" ] || die "--old-dmg and --new-dmg are required"
[ -n "$OLD_VERSION" ] && [ -n "$NEW_VERSION" ] || die "--old-version and --new-version are required"
case "$OLD_SHA" in sha256:*) ;; *) die "--old-sha must be sha256:<hex> from the sealed build" ;; esac
case "$NEW_SHA" in sha256:*) ;; *) die "--new-sha must be sha256:<hex> from the sealed build" ;; esac
[ -f "$OLD_DMG" ] || die "old DMG not found: $OLD_DMG"
[ -f "$NEW_DMG" ] || die "new DMG not found: $NEW_DMG"

[ -n "$RECEIPTS" ] || RECEIPTS="$HOME/clean-machine-receipts/$RUN_ID"
WORK="$HOME/clean-machine-work/$RUN_ID"
mkdir -p "$RECEIPTS" "$WORK/logs" "$WORK/uninstalled" "$WORK/previous" "$HOME/Downloads" "$APP_DIR" || die "cannot create work dirs"

HARNESS_SHA="sha256:$(shasum -a 256 "$SCRIPT_PATH" | awk '{print $1}')"
ENV_FILE="$WORK/env.tsv"
{
  printf 'host\t%s\n' "$(scutil --get ComputerName 2>/dev/null || hostname)"
  printf 'os_version\t%s %s (%s)\n' "macOS" "$(sw_vers -productVersion)" "$(sw_vers -buildVersion)"
  printf 'user\t%s\n' "$(id -un)"
  printf 'arch\t%s\n' "$(uname -m)"
} > "$ENV_FILE"

OBS_FILE=""; ART_FILE=""; CUR_ID=""; CUR_NAME=""; CUR_START=""
RUN_FAILS=0
APP_PID=""
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
  local status="$1" impl="$2" rc="$3" reason="$4" ended
  ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ "$status" = "pass" ] || RUN_FAILS=$((RUN_FAILS + 1))
  python3 -I - "$RECEIPTS" "$RUN_ID" "$CUR_ID" "$CUR_NAME" "$impl" "$status" "$reason" "$rc" \
    "$CUR_START" "$ended" "$OBS_FILE" "$ART_FILE" "$ENV_FILE" "$HARNESS_NAME" "$HARNESS_SHA" <<'PY'
import json, os, sys
(rdir, run, cid, name, impl, status, reason, rc, started, ended,
 obsf, artf, envf, hname, hsha) = sys.argv[1:16]

def kv(path, schema=str):
    out = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.rstrip("\n")
            if "\t" in line:
                k, v = line.split("\t", 1)
                out[k] = v
    return out

implemented = impl == "true"
if not implemented:
    status = "fail"
    reason = "not-implemented: " + (reason if reason != "-" else "no automated procedure")
rec = {
    "schema": "clean-machine-receipt/v1",
    "record": "check",
    "platform": "mac",
    "run_id": run,
    "check_id": cid,
    "check_name": name,
    "stage": "package",
    "status": status,
    "implemented": implemented,
    "reason": None if status == "pass" else (reason if reason != "-" else "failed"),
    "started_utc": started,
    "ended_utc": ended,
    "exit_status": None if rc == "-" else int(rc),
    "observed": kv(obsf),
    "artifact_ids": kv(artf),
    "environment": kv(envf),
    "harness": {"name": hname, "sha256": hsha},
}
os.makedirs(rdir, exist_ok=True)
with open(os.path.join(rdir, cid + ".json"), "w", encoding="utf-8") as f:
    json.dump(rec, f, indent=2, sort_keys=True)
    f.write("\n")
print(f"{cid}: {status}" + ("" if status == "pass" else f" ({rec['reason']})"), file=sys.stderr)
PY
}

# ---------------------------------------------------------------- helpers
sha_of() { if [ -f "$1" ]; then shasum -a 256 "$1" | awk '{print "sha256:"$1}'; else echo missing; fi; }

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }

offline_now() { ! route -n get default >/dev/null 2>&1; }

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

stop_app() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null; wait "$APP_PID" 2>/dev/null
  fi
  APP_PID=""
}

# launch_offline <label>: direct exec of the binary (no open(1)). Sets APP_PID; returns 0 if alive after 15 s.
launch_offline() {
  local exe="$APP_DIR/$APP_NAME/Contents/MacOS/$(plist "$APP_DIR/$APP_NAME" CFBundleExecutable)"
  "$exe" >"$WORK/logs/app-$CUR_ID-$1.log" 2>&1 &
  APP_PID=$!
  sleep 15
  if kill -0 "$APP_PID" 2>/dev/null; then
    obs "launch_$1_alive" "true"; return 0
  fi
  obs "launch_$1_alive" "false"; return 1
}

rows_schema_ok() {
  python3 -I - "$1" "$2" <<'PY'
import json, sys
path, want = sys.argv[1], int(sys.argv[2])
try:
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
except Exception as e:
    print(f"unparseable: {e}", file=sys.stderr); sys.exit(1)
sys.exit(0 if isinstance(doc, dict) and doc.get("schema") == want else 1)
PY
}

ROWS="$DATA_DIR/rows.json"

cleanup() {
  stop_app
  for m in "${MOUNTS[@]:-}"; do
    [ -n "$m" ] && hdiutil detach "$m" >/dev/null 2>&1
  done
}
trap cleanup EXIT

# ---------------------------------------------------------------- checks
echo "clean-machine run $RUN_ID (mac) receipts: $RECEIPTS" >&2

# M00: environment and offline precondition
check_begin M00-environment "Environment and offline precondition"
obs "user" "$(id -un)"; obs "arch" "$(uname -m)"; obs "os" "$(sw_vers -productVersion)"
obs "allowlist" "$ALLOWLIST"
if offline_now; then obs "default_route" "none"; else obs "default_route" "present"; fi
if [ "$(uname -m)" = "arm64" ] && offline_now; then
  check_finish pass true - -
else
  check_finish fail true - "arch must be arm64 and no default route (networking off)"
fi

# M01: artifacts bound to the sealed hashes
check_begin M01-artifacts-bound "Input DMGs match the sealed build hashes"
art old_dmg "$OLD_DMG"; art new_dmg "$NEW_DMG"
obs "old_version" "$OLD_VERSION"; obs "new_version" "$NEW_VERSION"
if [ "$(sha_of "$OLD_DMG")" = "$OLD_SHA" ] && [ "$(sha_of "$NEW_DMG")" = "$NEW_SHA" ]; then
  check_finish pass true - -
else
  check_finish fail true - "DMG hash does not match --old-sha/--new-sha"
fi

# M02: quarantined delivery (download simulation). Copies go to the test user's Downloads.
check_begin M02-quarantined-delivery "Quarantined delivery of both DMGs"
q_ok=1
for pair in "OLD:$OLD_DMG" "NEW:$NEW_DMG"; do
  tag="${pair%%:*}"; src="${pair#*:}"; dl="$HOME/Downloads/SliceApp-$tag-$RUN_ID.dmg"
  cp "$src" "$dl" || q_ok=0
  # flags 0081 (downloaded, quarantined), hex time, agent name, UUID
  xattr -w com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)" "$dl" 2>/dev/null || q_ok=0
  q="$(xattr -p com.apple.quarantine "$dl" 2>/dev/null)"
  obs "quarantine_${tag}" "${q:-missing}"
  [ -n "$q" ] || q_ok=0
  if [ "$tag" = "OLD" ]; then OLD_DL="$dl"; else NEW_DL="$dl"; fi
done
if [ "$q_ok" -eq 1 ]; then check_finish pass true - -; else check_finish fail true - "quarantine attribute missing on a copy"; fi

# M03: Gatekeeper assessment of the quarantined DMG and stapled ticket
check_begin M03-gatekeeper-dmg "Gatekeeper and stapler on the quarantined old DMG"
spctl --assess --type open --context context:primary-signature -v "$OLD_DL" >"$WORK/logs/gk-open-$CUR_ID.log" 2>&1; rc_gk=$?
xcrun stapler validate "$OLD_DL" >"$WORK/logs/stapler-$CUR_ID.log" 2>&1; rc_st=$?
obs "spctl_open_rc" "$rc_gk"; obs "stapler_rc" "$rc_st"
if [ "$rc_gk" -eq 0 ] && [ "$rc_st" -eq 0 ]; then
  check_finish pass true "$rc_gk" -
else
  check_finish fail true "$rc_gk" "spctl open rc=$rc_gk stapler rc=$rc_st"
fi

# M04: install the old build from its DMG (verify first, then copy)
check_begin M04-install-from-dmg "Install old build from DMG (verify before copy)"
install_from_dmg "$OLD_DL" "$OLD_VERSION" "$OLD_SHA"; rc_in=$?
art installed_binary "$APP_DIR/$APP_NAME/Contents/MacOS/$(plist "$APP_DIR/$APP_NAME" CFBundleExecutable 2>/dev/null)"
obs "install_rc" "$rc_in"
if [ "$rc_in" -eq 0 ]; then check_finish pass true "$rc_in" -; else check_finish fail true "$rc_in" "install_from_dmg rc=$rc_in"; fi

# M05: offline first launch; data file must be created at the declared path
check_begin M05-offline-first-launch "Offline first launch writes rows.json"
if offline_now; then
  if launch_offline first; then
    stop_app
    if [ -f "$ROWS" ] && rows_schema_ok "$ROWS" 1; then
      art rows_json_after_first_launch "$ROWS"; obs "rows_json" "present, schema 1"
      check_finish pass true - -
    else
      check_finish fail true - "rows.json missing or not schema 1 at $ROWS"
    fi
  else
    check_finish fail true - "app not alive after 15 s"
  fi
else
  check_finish fail true - "network is online; offline precondition not met"
fi

# M06: upgrade by DMG replace; rows.json unchanged by the install
check_begin M06-upgrade-dmg-replace "Upgrade by DMG replace keeps rows.json"
stop_app
pre_sha="$(sha_of "$ROWS" 2>/dev/null || echo missing)"
obs "rows_sha_before" "$pre_sha"
install_from_dmg "$NEW_DL" "$NEW_VERSION" "$NEW_SHA"; rc_up=$?
obs "install_rc" "$rc_up"
post_sha="$(sha_of "$ROWS" 2>/dev/null || echo missing)"
obs "rows_sha_after_install" "$post_sha"
if [ "$rc_up" -eq 0 ] && [ "$pre_sha" = "$post_sha" ] && [ "$pre_sha" != missing ] && launch_offline upgraded; then
  stop_app
  check_finish pass true "$rc_up" -
else
  check_finish fail true "$rc_up" "upgrade rc=$rc_up rows before=$pre_sha after=$post_sha"
fi

# M07: corrupt binary must be refused by the gate and must not replace the installed bundle
check_begin M07-corrupt-binary-rejected "Corrupt binary rejected by the install gate"
CORRUPT="$WORK/corrupt/$APP_NAME"; mkdir -p "$WORK/corrupt"; rm -rf "$CORRUPT"
ditto "$APP_DIR/$APP_NAME" "$CORRUPT"
EXEC_NAME="$(plist "$CORRUPT" CFBundleExecutable)"
installed_before="$(sha_of "$APP_DIR/$APP_NAME/Contents/MacOS/$EXEC_NAME")"
flip_info="$(python3 -I - "$CORRUPT/Contents/MacOS/$EXEC_NAME" <<'PY'
import sys
p = sys.argv[1]
b = bytearray(open(p, "rb").read())
off = len(b) // 2
before = b[off]
b[off] ^= 0x01
open(p, "wb").write(bytes(b))
print(f"{off}\t{before:02x}\t{b[off]:02x}")
PY
)"
obs "flipped_offset_before_after" "$flip_info"
verify_bundle "$CORRUPT" "$NEW_VERSION"; gate_rc=$?
installed_after="$(sha_of "$APP_DIR/$APP_NAME/Contents/MacOS/$EXEC_NAME")"
obs "gate_rc_on_corrupt" "$gate_rc"
obs "installed_binary_sha_before" "$installed_before"
obs "installed_binary_sha_after" "$installed_after"
if [ "$gate_rc" -ne 0 ] && [ "$installed_before" = "$installed_after" ]; then
  check_finish pass true "$gate_rc" -
else
  check_finish fail true "$gate_rc" "gate accepted corrupt bundle or installed bundle changed"
fi

# M08: interrupted install. Procedure not defined yet (close plan F6). Always FAILS.
check_begin M08-interrupted-install "Interrupted install at copy/swap boundaries"
interrupted_install_placeholder() { return 1; }
interrupted_install_placeholder; rc_int=$?
check_finish fail false "$rc_int" "procedure not defined; see close plan F6 and mac-clean-checklist.md step 8"

# M09: rollback readability (old build reads data written by the new build)
check_begin M09-rollback-readable "Old build reads data written by new build"
stop_app
pre_sha="$(sha_of "$ROWS" 2>/dev/null || echo missing)"
obs "rows_sha_before_rollback" "$pre_sha"
install_from_dmg "$OLD_DL" "$OLD_VERSION" "$OLD_SHA"; rc_rb=$?
obs "install_rc" "$rc_rb"
if [ "$rc_rb" -eq 0 ] && launch_offline rollback; then
  stop_app
  if rows_schema_ok "$ROWS" 1; then
    obs "rows_readable_by_old" "true"
    check_finish pass true "$rc_rb" -
  else
    obs "rows_readable_by_old" "false"
    check_finish fail true "$rc_rb" "rows.json not schema 1 after old launch"
  fi
else
  check_finish fail true "$rc_rb" "rollback install rc=$rc_rb or old build not alive"
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

# M11: window visible. Not automated (no stdlib-only window probe allowed here). Always FAILS until observed.
check_begin M11-window-visible "Window visible on first launch (manual observation)"
check_finish fail false - "requires a recorded manual observation; see mac-clean-checklist.md step 5"

# ---------------------------------------------------------------- run summary
python3 -I - "$RECEIPTS" "$RUN_ID" "$HARNESS_NAME" "$HARNESS_SHA" "${EXPECTED[@]}" <<'PY'
import glob, json, os, sys, datetime
rdir, run, hname, hsha, *expected = sys.argv[1:]
checks = []
by_id = {}
for path in sorted(glob.glob(os.path.join(rdir, "M*.json"))):
    with open(path, encoding="utf-8") as f:
        rec = json.load(f)
    by_id[rec["check_id"]] = rec
    checks.append({"check_id": rec["check_id"], "status": rec["status"], "implemented": rec["implemented"]})
missing = [c for c in expected if c not in by_id]
ok = not missing and all(by_id[c]["status"] == "pass" and by_id[c]["implemented"] for c in expected)
reason = None if ok else ("missing receipts: " + ", ".join(missing) if missing else "checks not passing: " + ", ".join(
    c for c in expected if c in by_id and by_id[c]["status"] != "pass"))
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
run_rec = {
    "schema": "clean-machine-receipt/v1", "record": "run", "platform": "mac", "run_id": run,
    "status": "pass" if ok else "fail", "expected_checks": expected, "checks": checks,
    "started_utc": now, "ended_utc": now, "reason": reason,
    "artifact_ids": {}, "harness": {"name": hname, "sha256": hsha},
}
with open(os.path.join(rdir, "run.json"), "w", encoding="utf-8") as f:
    json.dump(run_rec, f, indent=2, sort_keys=True); f.write("\n")
print(f"run {run}: {run_rec['status']}" + ("" if ok else f" ({reason})"), file=sys.stderr)
PY
run_rc=$?
[ "$RUN_FAILS" -eq 0 ] && [ "$run_rc" -eq 0 ] || exit 1
exit 0
