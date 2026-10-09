// swift-tools-version:6.0
import PackageDescription

// SR1Gallery (SR1 head start, Windows backend): one gallery screen per SR1 control on the fresh runtime
// (probes/sr0-s/fresh-runtime, module SwiftRightRuntime) driving the Windows renderer through bridge ABI 0.6
// (packages/SwiftRightBridge). Port of probes/sr0-s/fresh-on-bridge (SR0-S) with a scripted self-test.
// The Windows build needs the ComCtl v6 manifest link flags supplied by the consumer invocation
// (scripts/build-gallery.ps1), as for examples/BridgeSmoke. Nothing here edits fresh-runtime, render/ or packages/.
let package = Package(
    name: "SR1Gallery",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../sr0-s/fresh-runtime"),
        .package(path: "../../packages/SwiftRightBridge"),
    ],
    targets: [
        .executableTarget(
            name: "SR1Gallery",
            dependencies: [
                .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
                .product(name: "SwiftRightBridge", package: "SwiftRightBridge"),
            ],
            path: "Sources/SR1Gallery"
        ),
    ],
    swiftLanguageModes: [.v5]
)
