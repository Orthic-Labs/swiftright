// swift-tools-version:6.0
import PackageDescription
// I1 decode-dump host. The product (runtime + bridge + SwiftRightHost) is the staged tree of factory/tools/stage-product.py; run.py replaces @@PRODUCT_STAGE@@.
// Builds on Windows (WIC) and, with the same sources, on the Mac (ImageIO) for the Mac-side check.
let package = Package(name: "ImageDump", platforms: [.macOS(.v14)], dependencies: [
    .package(name: "fresh-runtime", path: "@@PRODUCT_STAGE@@/probes/sr0-s/fresh-runtime"),
    .package(path: "@@PRODUCT_STAGE@@/packages/SwiftRightHost")
], targets: [.executableTarget(name: "ImageDump", dependencies: [
    .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
    .product(name: "SwiftRightHost", package: "SwiftRightHost")
])], swiftLanguageModes: [.v5])
