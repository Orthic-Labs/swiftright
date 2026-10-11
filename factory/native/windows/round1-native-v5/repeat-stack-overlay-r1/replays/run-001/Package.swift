// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "FactoryProbe", dependencies: [
    .package(name: "fresh-runtime", path: "D:\\Claude\\factory-swiftright-module-origin-37429120-20261011\\runtime"), .package(path: "D:\\Claude\\sr0-r09\\src\\packages\\SwiftRightBridge")
], targets: [.executableTarget(name: "FactoryProbe", dependencies: [
    .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
    .product(name: "SwiftRightBridge", package: "SwiftRightBridge")
])], swiftLanguageModes: [.v5])
