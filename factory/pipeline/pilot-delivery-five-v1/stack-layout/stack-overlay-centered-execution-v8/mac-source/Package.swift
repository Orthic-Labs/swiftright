// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StackOverlayV6MacHost",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "StackOverlayV6MacHost", targets: ["StackOverlayV6MacHost"])],
    targets: [.executableTarget(name: "StackOverlayV6MacHost")],
    swiftLanguageModes: [.v5]
)
