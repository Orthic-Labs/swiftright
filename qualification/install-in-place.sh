# Sourced helper: install a signed .app at ONE fixed path, in place.
# Adrian's rule (2026-10-17): no new id, no new folder, for every app. Every app/helper lives at
# $SR_APP_DIR/<name>.app with one bundle id and one signing identity; the prior copy is kept beside it as
# <name>.previous.app (replacing an older .previous). Never run from a new path. The fixed dir is on the
# internal disk; never under /Volumes/D (that triggers privacy prompts).
SR_APP_DIR=${SR_APP_DIR:-$HOME/Applications/SwiftRight}
SR_TEAM_ID=6KLGD3LLKF
# Developer ID identity by name (never a certificate hash); override only with SR_SIGN_IDENTITY.
SR_SIGN_IDENTITY=${SR_SIGN_IDENTITY:-"Developer ID Application: Adrian D'souza ($SR_TEAM_ID)"}

# install_in_place <built.app> <name-without-.app> <expected-bundle-id>
install_in_place() {
  _src=$1; _name=$2; _id=$3
  case "$SR_APP_DIR" in "$HOME"/*) ;; *) echo "fixed app dir must be under HOME (internal disk): $SR_APP_DIR" >&2; return 2 ;; esac
  case "$SR_APP_DIR" in /Volumes/*) echo "fixed app dir must not be on an external volume: $SR_APP_DIR" >&2; return 2 ;; esac
  [ -d "$_src" ] || { echo "app to install missing: $_src" >&2; return 2; }
  # Refuse to put an unsigned or wrongly identified bundle at the fixed path: that would drop its privacy grants.
  /usr/bin/codesign --verify --strict "$_src" >/dev/null 2>&1 || { echo "not installed: $_src is not validly signed" >&2; return 3; }
  _info=$(/usr/bin/codesign -dv "$_src" 2>&1)
  printf '%s\n' "$_info" | grep -q "^TeamIdentifier=$SR_TEAM_ID\$" || { echo "not installed: team is not $SR_TEAM_ID" >&2; return 3; }
  printf '%s\n' "$_info" | grep -q "^Identifier=$_id\$" || { echo "not installed: bundle id is not $_id" >&2; return 3; }
  _dest="$SR_APP_DIR/$_name.app"; _prev="$SR_APP_DIR/$_name.previous.app"
  mkdir -p "$SR_APP_DIR" || return 1
  # Every step is checked explicitly: callers may run this inside `if`, which disables `set -e` in here.
  if [ -e "$_dest.incoming" ]; then rm -rf "$_dest.incoming" || return 1; fi
  mv "$_src" "$_dest.incoming" || return 1
  if [ -e "$_dest" ]; then
    rm -rf "$_prev" || { mv "$_dest.incoming" "$_src"; return 1; }
    mv "$_dest" "$_prev" || { mv "$_dest.incoming" "$_src"; return 1; }
  fi
  mv "$_dest.incoming" "$_dest" || {
    if [ -e "$_prev" ] && [ ! -e "$_dest" ]; then mv "$_prev" "$_dest"; fi
    mv "$_dest.incoming" "$_src" 2>/dev/null
    return 1
  }
  echo "installed: $_dest (previous: $_prev)"
  return 0
}
