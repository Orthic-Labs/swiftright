// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "Probe", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "..")],
    targets: [.executableTarget(name: "Probe", dependencies: [.product(name: "Combine", package: "SwiftRightCombine", condition: .when(platforms: [.windows, .linux]))])],
    swiftLanguageModes: [.v5])
