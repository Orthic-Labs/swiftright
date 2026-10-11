// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fresh-runtime",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftRightRuntime", targets: ["SwiftRightRuntime"]),
    ],
    targets: [
        .target(
            name: "SwiftRightRuntime",
            path: "runtime-candidate-sources/SwiftRightRuntime",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
