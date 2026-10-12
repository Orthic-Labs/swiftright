// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CustomLayoutMacMatchedScaleHost",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CustomLayoutMacMatchedScaleHost", targets: ["CustomLayoutMacMatchedScaleHost"])],
    targets: [.executableTarget(name: "CustomLayoutMacMatchedScaleHost")],
    swiftLanguageModes: [.v5]
)
