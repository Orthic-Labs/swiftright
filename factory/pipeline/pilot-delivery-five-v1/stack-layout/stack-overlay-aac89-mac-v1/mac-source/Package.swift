// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StackOverlayAAC89MacHost",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "StackOverlayAAC89MacHost", targets: ["StackOverlayAAC89MacHost"])],
    targets: [.executableTarget(name: "StackOverlayAAC89MacHost")],
    swiftLanguageModes: [.v5]
)
