// swift-tools-version: 6.0
// SwiftRightCombine (#88): a module named `Combine` for platforms without Apple's Combine (Windows, Linux), so SwiftUI source that says `import Combine`
// compiles unchanged. It re-exports OpenCombine (MIT, https://github.com/OpenCombine/OpenCombine) and adds the Apple-named API OpenCombine spells
// differently or lacks. Depend on the `Combine` product only for non-Apple platforms: on macOS the system Combine is used and this target is never built.
import PackageDescription

let package = Package(
    name: "SwiftRightCombine",
    products: [
        .library(name: "Combine", targets: ["Combine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", exact: "0.14.0"),
    ],
    targets: [
        .target(
            name: "Combine",
            dependencies: [
                .product(name: "OpenCombine", package: "OpenCombine"),
                .product(name: "OpenCombineFoundation", package: "OpenCombine"),
                .product(name: "OpenCombineDispatch", package: "OpenCombine"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
