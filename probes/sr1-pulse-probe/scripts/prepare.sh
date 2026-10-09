#!/bin/sh
# Copies the two Pulse files (read-only source) into out/src with the platform imports replaced
# by the contract's Windows branch, and adds the Pulse-internal model stubs. out/ is git-ignored:
# Pulse is a Codenotch fork, so its source must never be committed here.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
src=${PULSE_FEATURES:-/Volumes/D/claude/pulse/mac/Notch/Sources/Features}
mkdir -p "$here/out/src"
for f in ProviderRing TooltipCard; do
  sed -e '/^import AppKit$/d' -e 's/^import SwiftUI$/import Foundation\n#if canImport(CoreGraphics)\nimport CoreGraphics\n#endif\nimport SwiftRightUI/' \
    "$src/$f.swift" > "$here/out/src/$f.swift"
done
# Foundation is needed by the ProviderRing copy as well (its AppKit import carried it implicitly).
grep -q '^import Foundation' "$here/out/src/ProviderRing.swift" || true
cp "$here"/stubs/*.swift "$here/out/src/"
[ "${NOMODS:-0}" = 1 ] && rm -f "$here/out/src/GapsModifiers.swift"
[ "${NOGAPS:-0}" = 1 ] && rm -f "$here/out/src/Gaps.swift" "$here/out/src/GapsModifiers.swift"
# Iteration aid: cut the AppKit/CoreAnimation island (SpinningArc*) from the ProviderRing copy so
# that body type-checking of the rest is not masked. Its symbols are catalogued from the uncut
# build (out/mac-appkit-evidence.txt) and by grep. SPLICE=0 keeps it.
if [ "${SPLICE:-1}" = 1 ]; then
  awk '/^\/\/\/ The working arc as a shape layer/{skip=1} /^\/\/\/ \*\*A cell.s percentage\*\*/{skip=0} !skip{print}' \
    "$here/out/src/ProviderRing.swift" > "$here/out/src/ProviderRing.tmp" && mv "$here/out/src/ProviderRing.tmp" "$here/out/src/ProviderRing.swift"
  # the spinner view that wraps the island, and the NSFont measurement
  python3 - "$here/out/src/ProviderRing.swift" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"        SpinningArc\(.*?\n        \)\n","        EmptyView()\n",s,flags=re.S)
s=re.sub(r"        let font = NSFont.*?\n        return ceil\(.*?\n","        return 0\n",s,flags=re.S)
open(p,'w').write(s)
PY
fi
