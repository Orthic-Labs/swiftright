#!/bin/zsh
# Runs the I1 unit tests on the Mac from a working-tree copy on the INTERNAL disk (never builds on /Volumes/D): SwiftRightHost ImagePolicyTests and the runtime ImageOrientationTests / ImageDataTests.
set -e
here="${0:A:h}"; repo="${here:h:h:h}"
base="$HOME/Library/Caches/SwiftRightFactory/image-io/stage"; mkdir -p "$base"
for p in packages/SwiftRightBridge packages/SwiftRightHost probes/sr0-s/fresh-runtime; do
  mkdir -p "$base/$p"; rsync -a --delete --exclude .build --exclude out --exclude .swiftpm "$repo/$p/" "$base/$p/"
done
export SWR_I1_CORPUS="$here/corpus"
(cd "$base/probes/sr0-s/fresh-runtime" && swift test --filter "ImageOrientationTests|ImageDataTests" 2>&1 | tail -15)
(cd "$base/packages/SwiftRightHost" && swift test --filter "ImagePolicyTests|ImageDecoderTests" 2>&1 | tail -30)
