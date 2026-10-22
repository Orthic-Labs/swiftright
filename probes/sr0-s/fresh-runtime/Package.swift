// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fresh-runtime",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftRightRuntime", targets: ["SwiftRightRuntime"]),
    ],
    dependencies: [
        // #88: `import Combine` on Windows and Linux (OpenCombine-backed); macOS uses the system Combine and never builds it.
        .package(path: "../../../packages/SwiftRightCombine"),
    ],
    targets: [
        .target(
            name: "SwiftRightRuntime",
            dependencies: [.product(name: "Combine", package: "SwiftRightCombine", condition: .when(platforms: [.windows, .linux]))],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiftRightRuntimeTests",
            dependencies: ["SwiftRightRuntime"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
