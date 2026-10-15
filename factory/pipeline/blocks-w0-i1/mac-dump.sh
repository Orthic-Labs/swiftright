#!/bin/zsh
# Mac-side check of the I1 decode service: builds dump-host against a working-tree copy of the product on the INTERNAL disk, runs it on the corpus (ImageIO backend).
# usage: mac-dump.sh OUT_DIR [--old]      (no window; never builds on /Volumes/D)
set -e
here="${0:A:h}"; repo="${here:h:h:h}"
base="$HOME/Library/Caches/SwiftRightFactory/image-io/stage"; mkdir -p "$base"
for p in packages/SwiftRightBridge packages/SwiftRightHost probes/sr0-s/fresh-runtime; do
  mkdir -p "$base/$p"; rsync -a --delete --exclude .build --exclude out --exclude .swiftpm "$repo/$p/" "$base/$p/"
done
pkg="$base/dump-host"; mkdir -p "$pkg"; rsync -a --delete --exclude .build "$here/dump-host/" "$pkg/"
sed -i '' "s#@@PRODUCT_STAGE@@#$base#g" "$pkg/Package.swift"
(cd "$pkg" && swift build -c release --quiet 2>&1 | grep -E "error|warning: unre" | head -40 || true)
exec "$pkg/.build/release/ImageDump" "$here/corpus" "$@"
