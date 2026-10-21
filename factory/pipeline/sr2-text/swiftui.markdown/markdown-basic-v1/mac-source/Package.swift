// swift-tools-version:6.0
// Mac host with SwiftPM dependencies (factory/tools/pair.py builds it when this file exists; the sources in Sources/MacHost plus the shared tool sources form the target).
// Pins: swift-markdown-ui 2.4.1 (5f613358), its swift-cmark 0.5.0 (3ccff77b, per its Package.resolved) and NetworkImage 6.0.0, the same versions probes/markdownui-compat/fetch.sh builds for Windows.
import PackageDescription

let package = Package(
    name: "MacHost",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1"),
        .package(url: "https://github.com/swiftlang/swift-cmark", exact: "0.5.0"),
        .package(url: "https://github.com/gonzalezreal/NetworkImage", exact: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MacHost",
            dependencies: [.product(name: "MarkdownUI", package: "swift-markdown-ui")],
            path: "Sources/MacHost",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
