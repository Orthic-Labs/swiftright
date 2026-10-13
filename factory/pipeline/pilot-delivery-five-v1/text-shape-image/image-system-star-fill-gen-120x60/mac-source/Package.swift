// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "FactoryMacSourceProbe",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "FactoryProbe", path: "Sources/FactoryProbe")]
)
