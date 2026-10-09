// swift-tools-version: 6.0
// SR1 Pulse probe: compiles two Pulse SwiftUI files (copied into out/src by scripts/prepare.sh,
// never committed) against the fresh runtime. Expected to FAIL; the diagnostics are the product.
import PackageDescription

let package = Package(
    name: "sr1-pulse-probe",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../sr0-s/fresh-runtime")],
    targets: [
        .target(
            name: "SwiftRightUI",
            dependencies: [.product(name: "SwiftRightRuntime", package: "fresh-runtime")],
            path: "Sources/SwiftRightUI"
        ),
        .target(
            name: "PulseProbe",
            dependencies: ["SwiftRightUI"],
            path: "out/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
