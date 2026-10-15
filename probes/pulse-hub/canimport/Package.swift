// swift-tools-version:6.0
import PackageDescription
let stage = "@@PRODUCT_STAGE@@"
let package = Package(
    name: "CanImportProbe",
    products: [.library(name: "NoHostC", targets: ["NoHostC"]), .library(name: "HostDep", targets: ["HostDep"])],
    dependencies: [
        .package(name: "fresh-runtime", path: stage + "\\probes\\sr0-s\\fresh-runtime"),
        .package(path: stage + "\\packages\\SwiftRightHost"),
    ],
    targets: [
        // Mirrors RightKitHub's graph in the probe: depends on the SwiftUI shim (SwiftRightRuntime) but not on SwiftRightHost.
        .target(name: "NoHostC", dependencies: [.product(name: "SwiftRightRuntime", package: "fresh-runtime")], path: "Sources/NoHostC"),
        // The FactoryProbe host's graph: depends on SwiftRightHost.
        .target(name: "HostDep", dependencies: [.product(name: "SwiftRightHost", package: "SwiftRightHost")], path: "Sources/HostDep"),
    ]
)
