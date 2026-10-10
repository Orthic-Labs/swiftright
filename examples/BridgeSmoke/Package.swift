// swift-tools-version:6.0
import PackageDescription

// BridgeSmoke: Windows executable that exercises ABI v0 end to end through
// packages/SwiftRightBridge (window, hand-authored tree, measurement at two widths,
// AX Invoke, typed character, clean quit). Builds on macOS too (it then reports
// "unsupported platform" at run time).
//
// Windows build needs the ComCtl v6 manifest link flags (GPUI's TaskDialogIndirect):
//   swift build -c release -Xlinker /MANIFEST:EMBED -Xlinker /MANIFESTDEPENDENCY:"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
// (see scripts/build-smoke.ps1). The flags are supplied by the consumer invocation, not
// by a package manifest (no unsafeFlags).
let package = Package(
    name: "BridgeSmoke",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../packages/SwiftRightBridge"),
    ],
    targets: [
        .executableTarget(
            name: "BridgeSmoke",
            dependencies: [.product(name: "SwiftRightBridge", package: "SwiftRightBridge")],
            path: "Sources/BridgeSmoke"
        ),
        // SR0 T4: a fixed scene (image, text + underline, clips, translate) whose rendered pixels scripts/drive-pixels.ps1 asserts.
        .executableTarget(
            name: "BridgePixels",
            dependencies: [.product(name: "SwiftRightBridge", package: "SwiftRightBridge")],
            path: "Sources/BridgePixels"
        ),
    ],
    swiftLanguageModes: [.v5]
)
