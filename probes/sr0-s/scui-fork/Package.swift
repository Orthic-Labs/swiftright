// swift-tools-version: 6.0
import Foundation
import PackageDescription

// SCUI_STOCK=O1,O3 re-enables upstream behaviour for those SR0 overrides (ablation runs).
let stock: [SwiftSetting] = (ProcessInfo.processInfo.environment["SCUI_STOCK"] ?? "")
    .split(separator: ",").map { .define("SCUI_STOCK_\($0)") }

// SR0-S second seed: SwiftCrossUI core fork (upstream 0f3ec3958b79cdc39a1a3e604516b71ab33a9043).
// No macro plugin, no backends, no swift-syntax: the core is vendored with macro uses expanded by hand.
let package = Package(
    name: "scui-fork",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftCrossUI", targets: ["SwiftCrossUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/swhitty/swift-mutex", .upToNextMinor(from: "0.0.6")),
    ],
    targets: [
        .target(
            name: "SwiftCrossUI",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Mutex", package: "swift-mutex"),
            ],
            exclude: [  // gyb templates; the generated .swift files are vendored (never run gyb)
                "Builders/ViewBuilder.swift.gyb", "Builders/SceneBuilder.swift.gyb",
                "Builders/TableRowBuilder.swift.gyb", "Views/TupleView.swift.gyb",
                "Views/TupleViewChildren.swift.gyb", "Views/TableRowContent.swift.gyb",
                "Scenes/TupleScene.swift.gyb",
            ],
            swiftSettings: [.swiftLanguageMode(.v6)] + stock
        ),
        .target(
            name: "TestSinkBackend",
            dependencies: ["SwiftCrossUI"],
            swiftSettings: [.swiftLanguageMode(.v6)] + stock
        ),
        .testTarget(
            name: "ScuiForkTests",
            dependencies: ["SwiftCrossUI", "TestSinkBackend"],
            swiftSettings: [.swiftLanguageMode(.v6)] + stock
        ),
    ]
)
