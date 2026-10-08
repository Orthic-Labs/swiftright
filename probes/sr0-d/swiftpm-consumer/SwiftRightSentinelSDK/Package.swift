// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SwiftRightSentinelSDK",
    products: [
        .library(name: "SwiftRightSentinel", targets: ["SwiftRightSentinel"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSwiftRightSentinel",
            path: "Sources/CSwiftRightSentinel"
        ),
        .target(
            name: "SwiftRightSentinel",
            dependencies: ["CSwiftRightSentinel"],
            path: "Sources/SwiftRightSentinel"
        ),
    ]
)
