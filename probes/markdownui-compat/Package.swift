// swift-tools-version:6.0
// Mac-side compile probe (issue #68): MarkdownUI 2.4.1 type-checked against SwiftRightRuntime.
// `import SwiftUI` inside MarkdownUI resolves to the probe-only `SwiftUI` shim target (as in the Windows probe, docs/probes/markdownui-windows.md).
// Sources are fetched by fetch.sh at pinned commits (never committed). Run ./check.sh.
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]
let package = Package(
    name: "markdownui-compat",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MarkdownUI", targets: ["MarkdownUI"])],
    dependencies: [
        .package(name: "fresh-runtime", path: "../sr0-s/fresh-runtime"),
        .package(name: "swift-cmark", path: "vendor/swift-cmark"),
    ],
    targets: [
        .target(name: "SwiftUI", dependencies: [.product(name: "SwiftRightRuntime", package: "fresh-runtime")], swiftSettings: v5),
        // Stub of the surface MarkdownUI uses from NetworkImage (the real one does not build on Windows).
        .target(name: "NetworkImage", dependencies: ["SwiftUI"], swiftSettings: v5),
        .target(
            name: "MarkdownUI",
            dependencies: [
                "SwiftUI", "NetworkImage",
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            path: "vendor/swift-markdown-ui/Sources/MarkdownUI",
            swiftSettings: v5 + [.define("SWIFTRIGHT")]
        ),
    ]
)
