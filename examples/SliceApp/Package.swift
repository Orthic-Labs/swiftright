// swift-tools-version:6.0
import PackageDescription

// SliceApp: packageable SwiftRight example. One shared SwiftUI-shaped editor screen (same source on
// macOS and Windows) with SDK-owned bootstrap: a SwiftUI App on macOS, and on Windows the fresh runtime
// plus SwiftRightBridge (explicit renderer load, typed startup errors).
//
// Build:
//   macOS:    swift build -c release
//   Windows:  run scripts/build-windows.ps1 through `win` (ComCtl v6 + DPI manifest must be embedded
//             by the consumer link flags, not by this manifest: no unsafeFlags).
let package = Package(
    name: "SliceApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../probes/sr0-s/fresh-runtime"),
        .package(path: "../../packages/SwiftRightBridge"),
    ],
    targets: [
        .executableTarget(
            name: "SliceApp",
            dependencies: [
                .product(name: "SwiftRightRuntime", package: "fresh-runtime", condition: .when(platforms: [.windows])),
                .product(name: "SwiftRightBridge", package: "SwiftRightBridge", condition: .when(platforms: [.windows])),
            ],
            path: "Sources/SliceApp"
        ),
    ],
    swiftLanguageModes: [.v5]
)
