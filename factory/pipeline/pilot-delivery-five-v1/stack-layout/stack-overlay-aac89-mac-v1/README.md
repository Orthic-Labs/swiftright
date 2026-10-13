# Stack overlay aac89 Mac viewport packet v1

Source-only successor for paired Windows case `swiftui.stack-overlay.recipe/case/aac89c30fbc61515`. It preserves exact aac89 witness bytes (`sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee`) & renders it in fixed 320x240 points at scale 2.5, yielding expected 800x600 pixels. Host composition supplies opaque white background & light color scheme; witness is fixed-size & centered in viewport. No screen capture, AX query, or permission request is performed.

Mac source staging remains internal to `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1`. Root must run compile request through existing aggregate supervisor `factory/tools/supervise-job-v2.py` with 1 GiB bound. Prep/build scripts only stage source & emit request; no compile or native action occurs during source prep.

Typed joins:

- case: `swiftui.stack-overlay.recipe/case/aac89c30fbc61515`, hash `sha256:6b612bc12777ef3f5e6447d435128a3f805f8f990ece4eab9a91d9dec36f9cd0`
- recipe: `swiftui.stack-overlay.recipe`, hash `sha256:defb1db9e15fc29a4a6e959addb972ded0b0681bcddbde8c48529f849f1d1fd0`
- renderer: `sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`
- runtime: commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`, tree `sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e`

Root invocation after source review:

```sh
cd /Volumes/D/claude/swiftright/factory/pipeline/pilot-delivery-five-v1/stack-layout/stack-overlay-aac89-mac-v1/mac-source
./tools/prepare-mac-source.sh
# Root invokes emitted compile request with:
python3 /Volumes/D/claude/swiftright/factory/tools/supervise-job-v2.py \
  --seconds 600 --rss-mib 1024 --log-mib 128 \
  --out /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1/supervisor-receipt -- \
  swift build --package-path /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1/source \
  --scratch-path /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1/build \
  --jobs 1 -c release
# Binary directory: `swift build --package-path /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1/source --scratch-path /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1/build -c release --show-bin-path`; append `/StackOverlayAAC89MacHost`
# Observe:
"$(swift build --package-path /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1/source --scratch-path /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1/build -c release --show-bin-path)/StackOverlayAAC89MacHost" --preflight --scratch-root /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1/scratch/preflight
"$(swift build --package-path /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1/source --scratch-path /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1/build -c release --show-bin-path)/StackOverlayAAC89MacHost" --observe --scratch-root /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/stack-overlay-aac89-mac-v1/scratch/observe
```

Entry modes are `--preflight` & `--observe`, each with `--scratch-root` below internal cache prefix. Expected observation must join witness hash, case hash, source hash, fixed host points, render scale, image dimensions, white background, light scheme, & both rootRSS samples. This packet carries no qualification claim.
