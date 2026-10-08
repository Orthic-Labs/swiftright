// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BridgeFaults",
    targets: [
        // Header-only system module. No `link` directive: the renderer DLL is loaded explicitly.
        .systemLibrary(
            name: "CSwrFakeRender",
            path: "Sources/CSwrFakeRender"
        ),
        .executableTarget(
            name: "BridgeFaults",
            dependencies: ["CSwrFakeRender"],
            path: "Sources/BridgeFaults"
        ),
    ],
    swiftLanguageModes: [.v5]
)
