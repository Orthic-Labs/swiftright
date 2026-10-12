// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CustomLayoutRTLWidth32MacHost",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "CustomLayoutRTLWidth32MacHost", targets: ["CustomLayoutRTLWidth32MacHost"])],
    targets: [.executableTarget(name: "CustomLayoutRTLWidth32MacHost")],
    swiftLanguageModes: [.v5]
)
