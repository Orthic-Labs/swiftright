// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SameSource",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Probe", targets: ["Probe"]),
    ],
    targets: [
        // One target name. Platform-conditional implementation: real SwiftUI-named types are NOT declared on macOS.
        .target(name: "SwiftRightUI"),
        // Shared screen source. Must compile unchanged on macOS (SwiftUI) and Windows (SwiftRightUI stubs).
        .target(name: "SharedScreens", dependencies: ["SwiftRightUI"]),
        .executableTarget(name: "Probe", dependencies: ["SharedScreens", "SwiftRightUI"]),
    ],
    swiftLanguageModes: [.v6]
)
