// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ax-routes",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "FixtureApp", targets: ["FixtureApp"]),
        .executable(name: "AXRecorder", targets: ["AXRecorder"]),
    ],
    targets: [
        .executableTarget(name: "FixtureApp"),
        .executableTarget(name: "AXRecorder"),
    ],
    swiftLanguageModes: [.v6]
)
