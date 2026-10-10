// swift-tools-version:6.0
import PackageDescription

// BridgeGeoModal: two small Windows hosts on the ABI 0.6 bridge (packages/SwiftRightBridge), used for the
// SR0 snapshot rows 6 and 7 on the final tuple:
//   TextGeom06  text geometry (UIA TextPattern vs the measured cells), single- and multi-paragraph text
//   Modal06     the real SWR_MODAL_MENU / SWR_MODAL_DIALOG paths
// Both build on macOS too (they then report "unsupported platform" at run time; SWR_GM_DRYRUN=1 runs only the
// pure-logic self-test there). Windows build needs the ComCtl v6 manifest link flags: see scripts/build.ps1.
let package = Package(
    name: "BridgeGeoModal",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../packages/SwiftRightBridge"),
    ],
    targets: [
        .executableTarget(
            name: "TextGeom06",
            dependencies: [.product(name: "SwiftRightBridge", package: "SwiftRightBridge")],
            path: "Sources/TextGeom06"
        ),
        .executableTarget(
            name: "Modal06",
            dependencies: [.product(name: "SwiftRightBridge", package: "SwiftRightBridge")],
            path: "Sources/Modal06"
        ),
    ],
    swiftLanguageModes: [.v5]
)
