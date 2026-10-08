// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "comparator",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TraceKit", targets: ["TraceKit"]),
        .executable(name: "sr0o-trace", targets: ["TraceTool"]),
    ],
    targets: [
        .target(name: "TraceKit"),
        .executableTarget(name: "TraceTool", dependencies: ["TraceKit"]),
        .testTarget(
            name: "TraceKitTests",
            dependencies: ["TraceKit"],
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
