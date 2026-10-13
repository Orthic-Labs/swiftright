// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "FactoryTinosProbe", dependencies: [
    .package(name: "fresh-runtime", path: "D:\\Claude\\swiftright\\.factory-work\\runtime-stage\\runtime"),
    .package(path: "D:\\Claude\\swiftright\\.factory-work\\inputs\\SwiftRightBridge")
], targets: [.executableTarget(name: "FactoryProbe", dependencies: [
    .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
    .product(name: "SwiftRightBridge", package: "SwiftRightBridge")
])], swiftLanguageModes: [.v5])
