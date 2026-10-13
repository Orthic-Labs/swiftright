// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CustomLayoutMacHost",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "CustomLayoutMacHost", targets: ["CustomLayoutMacHost"])],
    targets: [.executableTarget(name: "CustomLayoutMacHost")],
    swiftLanguageModes: [.v5]
)
