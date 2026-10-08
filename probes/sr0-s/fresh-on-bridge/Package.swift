// swift-tools-version:6.0
import PackageDescription

// FreshOnBridge: the headless fresh runtime (probes/sr0-s/fresh-runtime, module
// SwiftRightRuntime) driving the real Windows renderer through bridge ABI v0
// (packages/SwiftRightBridge). Port of SR0-O fixture F1 with a scripted self-test.
// Windows build needs the ComCtl v6 manifest link flags supplied by the consumer
// invocation (scripts/build-fresh.ps1), as for examples/BridgeSmoke.
let package = Package(
    name: "FreshOnBridge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../fresh-runtime"),
        .package(path: "../../../packages/SwiftRightBridge"),
    ],
    targets: [
        .executableTarget(
            name: "FreshOnBridge",
            dependencies: [
                .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
                .product(name: "SwiftRightBridge", package: "SwiftRightBridge"),
            ],
            path: "Sources/FreshOnBridge"
        ),
    ],
    swiftLanguageModes: [.v5]
)
