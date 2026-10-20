// swift-tools-version: 6.0
import PackageDescription

// Mac-only spike for the F-path (sr1-decisions.md, "20 October: F-path delivery 1 is host-rasterised"): renders each of the 11 path cases with
// real SwiftUI (ImageRenderer, scale 2.5) and with SwiftRightRuntime's PathRasterizer, and prints the per-case error.
// Run from this directory:   swift run -c release PathParitySpike [--out /Volumes/D/scratch/pathspike]
let package = Package(
    name: "PathParitySpike",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "PathParitySpike",
            dependencies: [.product(name: "SwiftRightRuntime", package: "fresh-runtime")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
