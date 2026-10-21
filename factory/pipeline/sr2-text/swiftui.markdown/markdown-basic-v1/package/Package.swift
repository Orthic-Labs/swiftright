// swift-tools-version:6.0
import PackageDescription
// The product (SwiftRightHost = runtime + bridge + paint path) is staged once for all cases; pair.py replaces the token with the
// staged tree (factory/tools/stage-product.py: git archive of one commit). The renderer DLL is chosen per run (SWIFTRIGHT_RENDER_DLL).
// MarkdownUI is the SwiftRight-patched build of probes/markdownui-compat: ci_pair.py (prebuild.json) archives it next to the staged product and runs its fetch.sh
// (pinned sources + patches) before this package builds; its own `fresh-runtime` path (../sr0-s/fresh-runtime) is the staged runtime named below.
let package = Package(name: "FactoryProbe", dependencies: [
    .package(name: "fresh-runtime", path: "@@PRODUCT_STAGE@@\\probes\\sr0-s\\fresh-runtime"),
    .package(path: "@@PRODUCT_STAGE@@\\packages\\SwiftRightHost"),
    .package(name: "markdownui-compat", path: "@@PRODUCT_STAGE@@\\probes\\markdownui-compat")
], targets: [.executableTarget(name: "FactoryProbe", dependencies: [
    .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
    .product(name: "SwiftRightHost", package: "SwiftRightHost"),
    .product(name: "MarkdownUI", package: "markdownui-compat")
])], swiftLanguageModes: [.v5])
