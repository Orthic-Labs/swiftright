// swift-tools-version: 6.0
// SwiftRightCombine (#88): a module named `Combine` for platforms without Apple's Combine (Windows, Linux), so SwiftUI source that says `import Combine`
// compiles unchanged. It re-exports a vendored OpenCombine 0.14.0 (MIT, Vendor/README.md) and adds what OpenCombine lacks (CombineLatest, Merge).
// Depend on the `Combine` product only for non-Apple platforms: on macOS the system Combine is used and these targets are never built.
import PackageDescription

let package = Package(
    name: "SwiftRightCombine",
    products: [
        .library(name: "Combine", targets: ["Combine"]),
    ],
    targets: [
        .target(name: "COpenCombineHelpers", path: "Vendor/COpenCombineHelpers"),
        .target(
            name: "OpenCombine",
            dependencies: ["COpenCombineHelpers"],
            path: "Vendor/OpenCombine",
            exclude: [
                "RootProtocols.swift.gyb",
                "Concurrency/Publisher+Concurrency.swift.gyb",
                "Publishers/Publishers.Encode.swift.gyb",
                "Publishers/Publishers.MapKeyPath.swift.gyb",
                "Publishers/Publishers.Catch.swift.gyb",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(name: "OpenCombineDispatch", dependencies: ["OpenCombine"], path: "Vendor/OpenCombineDispatch", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "OpenCombineFoundation", dependencies: ["OpenCombine", "COpenCombineHelpers"], path: "Vendor/OpenCombineFoundation",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "Combine",
            dependencies: ["OpenCombine", "OpenCombineDispatch", "OpenCombineFoundation"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
