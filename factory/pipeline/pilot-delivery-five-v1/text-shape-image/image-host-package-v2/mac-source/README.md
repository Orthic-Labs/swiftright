# Mac source packet v2: named RGBA Image

`Sources/FactoryProbe/Witness.swift` is exact witness source & retains `Image("factory.rgba.square.v1")`; no `NSImage`, `Image(systemName:)`, `Bundle.module`, or default asset fallback. `CaptureHost.swift` derives from `factory/native/macos/CaptureHost.swift`, adds tagged observables, wraps witness in fixed 320x240 `ZStack(alignment: .topLeading)`, & keeps signed-recorder no-prompt checks.

`Resources/FactoryRGBA.xcassets` contains exact 4x4 RGBA PNG (`sha256:57b45fdbc5d9a86bbad5f547b6964e39ba0c872130c564877d306f61477f6bea`). Root stages fresh scratch, runs `xcrun actool` into `App.app/Contents/Resources/Assets.car`, then runs `App.app/Contents/MacOS/FactoryProbe`; named Image resolves through `Bundle.main`.

Same-source Mac evidence reports interpolated 4x4-to-32x32 quadrant boundaries. Root should crop 32x32 pixels from this capture & compare against sibling `../../sampling-reference.json`; this packet records evidence, not a Mac pixel qualification receipt.

Root must attach RSS supervision to compile process group with 1 GiB maximum before invoking scripts; scripts apply no local VM memory limit.

Root-only bounded commands:

```sh
sh tools/prepare-mac-source.sh /Volumes/D/claude/swiftright /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/<fresh-stage>
sh tools/provision-main-bundle-assets.sh <stage> /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/<app>.app
sh tools/compile-mac-source.sh <stage> /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/<app>.app
```

All measured hashes, captures, permission state, & parity fields remain pending root receipts; denied AX/screen channels stay held without prompt.
