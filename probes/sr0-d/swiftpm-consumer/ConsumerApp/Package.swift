// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ConsumerApp",
    dependencies: [
        .package(path: "../SwiftRightSentinelSDK"),
    ],
    targets: [
        .executableTarget(
            name: "ConsumerApp",
            dependencies: [
                .product(name: "SwiftRightSentinel", package: "SwiftRightSentinelSDK"),
            ],
            path: "Sources/ConsumerApp"
        ),
    ]
)
