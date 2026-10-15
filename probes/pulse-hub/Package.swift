// swift-tools-version:6.0
// Probe package: Pulse's RightKitHub + PulseHub(+Fixtures) compiled for Windows against the SwiftRight runtime.
// Assembled by assemble.sh (Pulse sources are fetched by SHA, never committed). Language mode 5 like every case host.
import PackageDescription

let stage = "@@PRODUCT_STAGE@@"
let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]
let package = Package(
    name: "PulseHubProbe",
    dependencies: [
        .package(name: "fresh-runtime", path: stage + "\\probes\\sr0-s\\fresh-runtime"),
        .package(path: stage + "\\packages\\SwiftRightHost"),
    ],
    targets: [
        .target(name: "SwiftUI", dependencies: [.product(name: "SwiftRightRuntime", package: "fresh-runtime")], swiftSettings: v5),
        .target(name: "CRightKitEngine"),
        .target(name: "RightKitEngine", dependencies: ["CRightKitEngine"], swiftSettings: v5),
        .target(name: "RightKitHub", dependencies: ["RightKitEngine", "SwiftUI",
            .product(name: "SwiftRightHost", package: "SwiftRightHost")], swiftSettings: v5),
        .target(name: "RightKitHubQA", dependencies: ["RightKitHub", "SwiftUI"], swiftSettings: v5),
        .target(name: "PulseHub", dependencies: ["RightKitHub", "SwiftUI"], swiftSettings: v5),
        .target(name: "PulseHubFixtures", dependencies: ["PulseHub", "RightKitHubQA", "SwiftUI"], swiftSettings: v5),
        // The capture host (host/): the executable the Sandbox capture job launches (its name is the job's process filter).
        .executableTarget(name: "FactoryProbe", dependencies: ["PulseHub", "PulseHubFixtures", "RightKitHub", "RightKitHubQA", "SwiftUI",
            .product(name: "SwiftRightRuntime", package: "fresh-runtime"), .product(name: "SwiftRightHost", package: "SwiftRightHost")],
            path: "Sources/FactoryProbe", swiftSettings: v5),
    ]
)
