#!/bin/sh
# Type-check MarkdownUI 2.4.1 against SwiftRightRuntime (Mac). Writes unique errors to $OUT.
cd "$(dirname "$0")"
./fetch.sh >/dev/null || exit 2
OUT=${OUT:-/Volumes/D/scratch/mdui-compat-errors.txt}
swift build --scratch-path /Volumes/D/scratch/mdui-compat-build --target MarkdownUI 2>&1 | tee /Volumes/D/scratch/mdui-compat-build.log | grep -E "error:" | sed -E 's#^.*/Sources/MarkdownUI/##' | sort -u > "$OUT"
echo "unique errors: $(wc -l < "$OUT")"
grep -q "Build complete" /Volumes/D/scratch/mdui-compat-build.log && echo "BUILD COMPLETE"
