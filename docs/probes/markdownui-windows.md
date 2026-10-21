# MarkdownUI on Windows through SwiftRight: probe

Date: 14 October 2026. Requested by RightKit session "Rk3" (Pulse hub rebuild in SwiftUI). Probe only: nothing in the product changed.

**Verdict: FAIL.** `swift-markdown-ui` 2.4.1 does not compile against the SwiftRight runtime. `import SwiftUI` does not resolve at all; with a probe-only shim that makes it resolve, 90 unique compiler errors remain in 34 groups (a lower bound, see "Method limits"). Nothing rendered, so nothing was verified beyond the compile result. `swift-cmark` builds on Windows; `NetworkImage` does not.

## What was fetched

| Item | Version | Commit | Where |
|---|---|---|---|
| gonzalezreal/swift-markdown-ui | 2.4.1, latest release (published 2024-10-13, `gh release view`) | `5f613358148239d0292c0cef674a3c2314737f9e` | cloned (depth 1) into a new empty scratchpad dir; 126 Swift files in `Sources/MarkdownUI` |
| swiftlang/swift-cmark | 0.5.0 (the version `Package.resolved` pins) | `3ccff77b2dc5b96b77db3da0d68d28068593fa53` | same dir |
| gonzalezreal/NetworkImage | 6.0.0 (pinned) | `7aff8d1b31148d32c5933d75557d42f6323ee3d1` | same dir |

MarkdownUI's `Package.swift` also lists swift-snapshot-testing 1.12.0 for its test target only; tests were not built.

## How SwiftRight compiles app SwiftUI source for Windows

The case hosts do not import SwiftUI on Windows. Every `Witness.swift` starts with `#if os(Windows) import SwiftRightRuntime #else import SwiftUI #endif` (for example `factory/pipeline/blocks-11-16/swiftui.button/prominent-v1/package/Sources/FactoryProbe/Witness.swift:1-5`), and the case `Package.swift` depends on the staged `probes/sr0-s/fresh-runtime` product `SwiftRightRuntime` plus `packages/SwiftRightHost` (`.../package/Package.swift`; staging by `factory/tools/stage-product.py`). There is no module named `SwiftUI` on Windows. Library source that says plain `import SwiftUI` (as all of MarkdownUI does, 71 files) therefore needs either a source change or a shim.

## Method

Dell, headless `swift build` only (toolchain `6.4.0+Asserts`, `x86_64-unknown-windows-msvc`, language mode 5), `--jobs 2`, in staged dirs under `D:\Claude\swiftright\.work\mdui-probe-20261014b\`. Runtime: product stage `09e184945-cc18ed0f` (existing, read-only). MarkdownUI and NetworkImage sources were copied unmodified (Tests and `Package.resolved` left out). No GUI, nothing in the Sandbox, nothing deleted.

| Variant | What it is | Result |
|---|---|---|
| A, `baseline` | MarkdownUI unmodified; dependencies are only the runtime and swift-cmark | stops at the first file: `error: no such module 'SwiftUI'` (`baseline.log`) |
| B1, `probe` with the real NetworkImage | a probe-only target named `SwiftUI` (`@_exported import SwiftRightRuntime` and `@_exported import Foundation`, as real SwiftUI re-exports Foundation) | NetworkImage fails first: `NetworkImageCache.swift:1:8: error: no such module 'CoreGraphics'` |
| B2, `probe` with NetworkImage replaced by a stub | stub = only the surface MarkdownUI uses (`NetworkImage` view, `NetworkImageState`, `DefaultNetworkImageLoader.shared.image(from:)`, a placeholder `CGImage`) | MarkdownUI: 90 unique errors (below) |

The shim target and the stub are probe-only and not committed as product. Without `@_exported import Foundation` the first B2 attempt had 90 errors too but dominated by `CGFloat`/`CGRect` not found; those are shim artefacts and are excluded from the table.

Evidence: all 90 errors with file:line:col in `docs/probes/evidence/markdownui-windows-errors.txt`. Raw logs stay on the Dell: `D:\Claude\swiftright\.work\mdui-probe-20261014b\{baseline,probe,probe2,probe3}.log`.

## Compile failures, grouped by missing API (variant B2)

Counts are unique file:line sites. "Runtime has it" is checked against `probes/sr0-s/fresh-runtime/Sources/SwiftRightRuntime`.

| Missing or different API | Sites | First site | Note |
|---|---|---|---|
| `AnyView` | 6 | `Extensibility/ImageProvider.swift:30` | no type-erased view; breaks `BlockConfiguration.Label`, `CodeBlockConfiguration.Label`, `TableCellConfiguration.Label`, `BlockStyle` (which all conform `View` through it) |
| ViewBuilder isolation: "call to main actor-isolated static method `buildBlock`/`buildExpression` in a synchronous nonisolated context" | 10 | `Theme/Theme.swift:122` | the runtime's `View`/`ViewBuilder` are `@MainActor`; MarkdownUI's `Theme` builders are not isolated. Structural, not a missing symbol |
| `View.fixedSize()` | 4 | `Theme/Theme+Basic.swift:109` | |
| `View.background(...)` (on `ScrollView`) | 2 | `Theme/Theme+DocC.swift:108` | also absent in the hub gap probe (P25, P26) |
| `View.overlay(Color)` shape: `overlay(_:alignment:)` with a style | 3 | `Theme/Theme+DocC.swift:145` | runtime `overlay` takes `alignment:content:` only |
| `Font.Width`, `Font.TextStyle` | 5 | `Theme/TextStyle/Styles/FontProperties.swift:100` | `Font` is a runtime struct without these members |
| `Text.LineStyle` (underline/strikethrough style) | 4 | `Theme/TextStyle/Styles/StrikethroughStyle.swift:5` | |
| `AttributeScopes.SwiftUIAttributes` (`SwiftUIAttributes`) | 1 | `Theme/TextStyle/Styles/FontPropertiesAttribute.swift:14` | MarkdownUI builds `AttributedString` runs with SwiftUI attributes; `AttributedString` itself is used in 11 places |
| `Anchor`, `GeometryProxy`, `GeometryReader`, `anchorPreference`, `backgroundPreferenceValue`, `PreferenceKey` conformance with `Anchor` values | 7 | `Views/Blocks/TableBounds.swift:20-124` | the table layout depends on anchor preferences |
| `StrokeStyle` | 2 | `Theme/BlockStyle/TableBorderStyle.swift:41` | same gap as the hub probe (P05) |
| `AnyShapeStyle` | 1 | `Theme/BlockStyle/TableBackgroundStyle.swift:31` | |
| `TextAlignment`, `EnvironmentValues.multilineTextAlignment` | 2 | `Views/Blocks/BlockSequence.swift:9,59` | |
| `AlignmentID`, `ViewDimensions`, custom `VerticalAlignment` | 5 | `Views/Blocks/ListItemView.swift:50-57` | custom alignment guides; the runtime's `VerticalAlignment` initializer is internal |
| `LabelStyle`, `LabelStyleConfiguration` | 2 | `Views/Blocks/ListItemView.swift:60-61` | |
| `ViewModifier`, `openURL`, `Content` | 5 | `Views/Inlines/ImageView.swift:66-78` | `ViewModifier` is not found in the runtime |
| `symbolRenderingMode` | 1 | `Theme/Theme+GitHub.swift:134` | |
| `Label` member on `BlockConfiguration.Label` (follow-on of the `AnyView` group) | 2 | `Theme/Theme+GitHub.swift:36` | cascade |
| Unknown attribute | 1 | `Views/Markdown.swift:288` | |
| `URLSession` ("moved to the FoundationNetworking module") | 2 | `Utility/Deprecations.swift:7,14` | Foundation networking on Windows |
| `PlatformImage` (`UIImage`/`NSImage`, `canImport(UIKit/AppKit)` both false) | 2 | `Extensibility/AssetImageProvider.swift:40,69` | AppKit/UIKit only |

Several groups cascade (the three `Label` conformance errors and the `Theme+GitHub` follow-ons come from `AnyView`; `ListItemView.swift:50` from `AlignmentID`). Distinct root causes: about 20 missing public SwiftUI types or modifiers plus the MainActor isolation mismatch.

## Dependencies that cannot build on Windows

| Dependency | Builds? | Evidence |
|---|---|---|
| swift-cmark 0.5.0 (`cmark-gfm`, `cmark-gfm-extensions`, C) | **Yes**, both libraries | `swift build --product cmark-gfm` and `--product cmark-gfm-extensions`: "Build complete" on the Dell. Its manifest has a Windows branch (`CMARK_GFM_STATIC_DEFINE`) |
| NetworkImage 6.0.0 | **No** | `no such module 'CoreGraphics'` (`NetworkImageCache.swift:1`); also imports `ImageIO` (`NetworkImageLoader.swift:3`, `CGImageSource*`), `NSCache<NSURL, CGImage>` (`NetworkImageCache.swift:21`), `URLSession` and `URLSessionConfiguration` (`URLSession+NetworkImage.swift`), and a `canImport(UIKit)` branch (`NetworkImage.swift:214`). Foundation networking, CoreGraphics and ImageIO are all unavailable or moved |
| Foundation networking | `URLSession` needs `import FoundationNetworking` on Windows; MarkdownUI uses it only in two deprecated initialisers (`Utility/Deprecations.swift:7,14`) | compiler message above |
| AppKit/UIKit | MarkdownUI: `Extensibility/AssetImageProvider.swift:41-72`, `Utility/Color+RGBA.swift:20-39` (`UIColor`/`NSColor` branches). Both fall through on Windows, `PlatformImage` is undefined | grep and compiler error |

## What was not verified

- No render. The module does not compile, so no sample (headings, lists, code block, table, links) was drawn, headless or otherwise.
- The compiler reports type-check errors per file but stops a module early for some failures, so 90 is a lower bound: later problems are masked. MarkdownUI uses things no error has reached yet, for example `Layout` (2 sites), `AttributedString` runs (11), `ScrollView` with `.horizontal` (3), `Grid` (1), `.relativeLineSpacing` (23) and `.task` (20).
- Whether MarkdownUI's `AttributedString` output could be shown at all on Windows depends on Foundation's `AttributedString` plus runtime `Text(AttributedString)`, which was not tested.

## What it would take (not done)

Roughly: a public `AnyView`, `ViewModifier`, `GeometryReader`/`Anchor`/`anchorPreference`, `fixedSize`, `background`, custom `AlignmentID`, `Font.Width`/`TextStyle`, `Text.LineStyle`, `TextAlignment`, `StrokeStyle`, `LabelStyle`, a SwiftUI-attribute scope for `AttributedString`, and a Windows replacement for NetworkImage. That is a large runtime surface compared with the 20 delivered blocks; for the hub a purpose-built Markdown view over the proven controls (Text, VStack, HStack, Rectangle, List) with swift-cmark as the parser is the smaller path, and swift-cmark is already proven to build on Windows. This is an observation from the error list, not a plan.

## Reproduce

Sources of the probe (shim, stub, two manifests) are small: `Package.swift` for `probe` has targets `SwiftUI` (shim), `NetworkImage` (stub or real), `MarkdownUI`, with the pinned swift-cmark as a path package and the runtime at the stage path; variant A is the same without the shim. The shim is two lines: `@_exported import SwiftRightRuntime` and `@_exported import Foundation`. Build with `swift build --package-path <dir> --scratch-path <dir> --jobs 2` using the toolchain at `C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin`.

## 21 October: compiles on the Mac against SwiftRight (#68)
MarkdownUI 2.4.1 now type-checks with zero errors against the SwiftRight runtime: `probes/markdownui-compat/check.sh` prints "unique errors: 0, BUILD COMPLETE".
- **How the probe works:**
  - Sources are pinned (MarkdownUI 5f613358, swift-cmark 3ccff77b).
  - A `SwiftUI` shim module re-exports the runtime, plus Foundation and, on Apple platforms, CoreGraphics.
  - A NetworkImage stub returns `RGBAImage`.
- **Vendor patches** (`probes/markdownui-compat/patches/`), active under `SWIFTRIGHT`:
  - The asset image provider resolves images by name, because there is no UIKit or AppKit image type.
  - `Color(light:dark:)` uses the light value.
- **Runtime APIs added** (three passes): the SwiftUI AttributedString scope, Text.LineStyle, Font variants, custom alignment guides, Grid, anchor preferences, LabelStyle, AnyShapeStyle, transformEnvironment/transformPreference, OpenURLAction, @ScaledMetric, lineSpacing and multilineTextAlignment (both carried), `LayoutSubview.priority`, and the CGSize-first `sizeThatFits`.
- **Windows (Dell, toolchain 6.4.0):** `swift build --target MarkdownUI` completes (exit 0). It needed patch 0003, which reads cmark's extension node types by parsing a sample, because Windows has no dlopen or dlsym. The probe shim also re-exports FoundationNetworking for URLSession.
- **Not done yet:**
  - A rendered sample.
  - Styled Text runs: inline bold, italic, code and links render as plain characters, and inline images are not drawn.
  - `multilineTextAlignment` and `lineSpacing` are carried but not applied by Text layout.
