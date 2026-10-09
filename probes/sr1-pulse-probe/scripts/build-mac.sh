#!/bin/sh
cd "$(dirname "$0")/.." && scripts/prepare.sh && swift build --target PulseProbe > "${1:-out/mac-build.txt}" 2>&1
scripts/errs.sh "${1:-out/mac-build.txt}"
