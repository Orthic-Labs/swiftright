# ScrollView axis initializer patch

`0001-scroll-view-axes.patch` adds `Axis`/`Axis.Set` plus `ScrollView.init(_:showsIndicators:content:)` to isolated fresh-runtime baseline. Existing content-only init stays on legacy `.scroll`; configured init uses new `.scrollView` case. Configured layout measures unbounded content along enabled axes, clamps axis offsets independently, and accepts indicators as stored headless config.

Patch target is `probes/sr0-s/fresh-runtime` at base `db29fd6dc240f10b8fe4cf9c1cad2fd18ea88343` for later integration. The patch adds typed axis configuration to headless layout & graph offsets; indicator rendering/native clipping metadata remains outside this runtime-only change.

Private working copy: `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions/scroll/fresh-runtime`.

Validation: `swift test` passed 139 tests, 0 failures on 11 Oct 2026. Base suite had 135 tests; this patch adds 4 axis, clamping, & same-identity cache-invalidation tests. Log: `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions/scroll/fresh-runtime-db29/probes/sr0-s/fresh-runtime/out/swift-test-scroll-db29.txt`.
