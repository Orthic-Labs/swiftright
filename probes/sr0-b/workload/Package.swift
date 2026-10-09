// swift-tools-version:6.0
import PackageDescription
import Foundation

// SR0 plan v2 lane R10: the architecture section 11 decision-budget workload, one source for both OSes.
//
//   WorkloadCore   shared model + screen (same source). Flavour is chosen at manifest time:
//                    runtime flavour = SwiftRightRuntime (the fresh runtime; Windows, or any host with WORKLOAD_FLAVOR=runtime)
//                    swiftui flavour = real SwiftUI (macOS)
//   WorkloadWin    Windows host: the runtime on the real renderer through bridge ABI 0.6 (instrumented).
//   WorkloadMac    macOS host: the real SwiftUI app (instrumented in-process).
//   SckRecorder    macOS recorder: separate process, input poster + ScreenCaptureKit visible-response detector.
//
// WORKLOAD_FLAVOR=runtime on macOS type-checks the Windows flavour (the bridge compiles on macOS; Bridge.load
// throws there). The Windows build never needs the variable.
#if os(Windows)
let runtimeFlavour = true
#else
let runtimeFlavour = ProcessInfo.processInfo.environment["WORKLOAD_FLAVOR"] == "runtime"
#endif

var packageDependencies: [Package.Dependency] = []
var coreDependencies: [Target.Dependency] = []
var targets: [Target] = []
var products: [Product] = []
let flavourSettings: [SwiftSetting] = runtimeFlavour ? [.define("WORKLOAD_RUNTIME")] : []

if runtimeFlavour {
    packageDependencies = [
        .package(path: "../../sr0-s/fresh-runtime"),
        .package(path: "../../../packages/SwiftRightBridge"),
    ]
    coreDependencies = [.product(name: "SwiftRightRuntime", package: "fresh-runtime")]
}

targets.append(.target(name: "WorkloadCore", dependencies: coreDependencies, path: "Sources/WorkloadCore", swiftSettings: flavourSettings))

if runtimeFlavour {
    targets.append(.executableTarget(
        name: "WorkloadWin",
        dependencies: [
            "WorkloadCore",
            .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
            .product(name: "SwiftRightBridge", package: "SwiftRightBridge"),
        ],
        path: "Sources/WorkloadWin",
        swiftSettings: flavourSettings
    ))
    products.append(.executable(name: "WorkloadWin", targets: ["WorkloadWin"]))
} else {
    targets.append(.executableTarget(name: "WorkloadMac", dependencies: ["WorkloadCore"], path: "Sources/WorkloadMac"))
    targets.append(.executableTarget(name: "SckRecorder", path: "Sources/SckRecorder"))
    products.append(.executable(name: "WorkloadMac", targets: ["WorkloadMac"]))
    products.append(.executable(name: "SckRecorder", targets: ["SckRecorder"]))
}

let package = Package(
    name: "SR0Workload",
    platforms: [.macOS(.v15)],
    products: products,
    dependencies: packageDependencies,
    targets: targets,
    swiftLanguageModes: [.v5]
)
