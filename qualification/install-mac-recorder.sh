#!/bin/sh
# Install a signed F1MacRecord.app at the one fixed path (in place, previous kept as F1MacRecord.previous.app).
# Usage: install-mac-recorder.sh <signed-F1MacRecord.app>   (built by prepare-mac-recorder.sh, then signed)
# The SOURCE BUNDLE IS NEVER MOVED OR MODIFIED: it is copied (ditto, signature preserved) into a staging dir inside
# the fixed app dir, and the copy is installed. This keeps e.g. probes/sr0-o/f1-cross/out/signed/F1MacRecord.app
# (the only signed recorder and the Info.plist template for prepare-mac-recorder.sh) in place.
set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/install-in-place.sh"
APP=${1:?usage: install-mac-recorder.sh <signed-F1MacRecord.app>}
[ -d "$APP" ] || { echo "app missing: $APP" >&2; exit 2; }
mkdir -p "$SR_APP_DIR"
STAGE=$(mktemp -d "$SR_APP_DIR/.staging.XXXXXX")
/usr/bin/ditto "$APP" "$STAGE/F1MacRecord.app"
rc=0
install_in_place "$STAGE/F1MacRecord.app" F1MacRecord com.orthiclabs.swiftright.f1macrecord || rc=$?
rm -rf "$STAGE"
exit "$rc"
