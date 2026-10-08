// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "fixtures",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "FixtureApp", targets: ["FixtureApp"]),
    ],
    targets: [
        // Shared slice screens, fake engine, instrumentation and step driver.
        .target(name: "SliceFixtures"),
        .executableTarget(name: "FixtureApp", dependencies: ["SliceFixtures"]),
    ],
    swiftLanguageModes: [.v6]
)
