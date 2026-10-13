// swift-tools-version:6.0
import PackageDescription
// The product (SwiftRightHost = runtime + bridge + paint path) is staged once for all cases; pair.py replaces the token with the
// staged tree (factory/tools/stage-product.py: git archive of one commit). The renderer DLL is chosen per run (SWIFTRIGHT_RENDER_DLL).
let package = Package(name: "FactoryProbe", dependencies: [
    .package(name: "fresh-runtime", path: "@@PRODUCT_STAGE@@\\probes\\sr0-s\\fresh-runtime"),
    .package(path: "@@PRODUCT_STAGE@@\\packages\\SwiftRightHost")
], targets: [.executableTarget(name: "FactoryProbe", dependencies: [
    .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
    .product(name: "SwiftRightHost", package: "SwiftRightHost")
])], swiftLanguageModes: [.v5])
