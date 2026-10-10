// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "FactoryProbe", dependencies: [
    .package(name: "fresh-runtime", path: "D:\\Claude\\factory-swiftright-final-67b841fb-20261011\\runtime"), .package(path: "D:\\Claude\\sr0-r10\\src\\packages\\SwiftRightBridge")
], targets: [.executableTarget(name: "FactoryProbe", dependencies: [
    .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
    .product(name: "SwiftRightBridge", package: "SwiftRightBridge")
])], swiftLanguageModes: [.v5])
