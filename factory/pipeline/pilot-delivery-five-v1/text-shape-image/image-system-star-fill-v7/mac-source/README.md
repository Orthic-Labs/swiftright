# Mac source observation: original system image

`Sources/FactoryProbe/Witness.swift` is exact original witness: `Image(systemName: "star.fill")`, `resizable`, `scaledToFit`, 32x32 frame, yellow foreground, light scheme. `CaptureHost.swift` wraps this unmodified witness in fixed 320x240 top-leading root, emits tagged geometry/pixel observations, & keeps no-prompt permission checks. No named asset, NSImage, or fixture substitution is used.

Root may use bounded internal-disk Mac source staging scripts in this packet with probe tag `swiftui.image.system-star-fill.v7`. Keep compiler/app scratch under `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/`; no `/Volumes/D` native build. Capture remains observational until root archives source, compiler, permission, screenshot, & exact pixel receipts.
