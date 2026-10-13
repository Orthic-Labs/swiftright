// swift-tools-version:6.0
import PackageDescription

// SwiftRightHost: the product-side glue between the fresh runtime (resolved tree) and SwiftRightBridge
// (ABI paint). It owns everything an app needs to paint what SwiftUI source resolves, so a plain
// SwiftUI-source app gets the behaviour with no per-case adapter:
//   - shape paint, including `RoundedRectangle(style: .continuous)` (rasterised, registered as an image),
//   - `Image(systemName:)` through the shipped symbol table and the Windows glyph provider,
//   - text measurement for the live body font, bundled `Font.custom` families and `.lineLimit(1)`.
// Layout (a package path dependency on both siblings keeps one source tree: stage the repo layout as is).
let package = Package(
    name: "SwiftRightHost",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftRightHost", targets: ["SwiftRightHost"]),
    ],
    dependencies: [
        .package(path: "../../probes/sr0-s/fresh-runtime"),
        .package(path: "../SwiftRightBridge"),
    ],
    targets: [
        .target(
            name: "SwiftRightHost",
            dependencies: [
                .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
                .product(name: "SwiftRightBridge", package: "SwiftRightBridge"),
            ]
        ),
        .testTarget(
            name: "SwiftRightHostTests",
            dependencies: ["SwiftRightHost"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
