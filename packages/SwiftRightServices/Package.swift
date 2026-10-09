// swift-tools-version:6.0
import PackageDescription

// SwiftRightServices: Swift EngineService client for Rust engines that speak the
// RightKit framed-sidecar wire envelope (rightkit-framed-sidecar src/wire.rs).
// Foundation only. Builds on macOS and Windows.
//
// - SwiftRightServices: EngineClient actor, framing codecs, typed errors, JSON helpers.
// - FakeEngine: independent Swift peer that speaks the same wire contract; used by tests.
let package = Package(
    name: "SwiftRightServices",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftRightServices", targets: ["SwiftRightServices"]),
    ],
    targets: [
        .target(name: "SwiftRightServices"),
        .executableTarget(name: "FakeEngine"),
        .testTarget(
            name: "SwiftRightServicesTests",
            dependencies: ["SwiftRightServices", "FakeEngine"]
        ),
    ]
)
