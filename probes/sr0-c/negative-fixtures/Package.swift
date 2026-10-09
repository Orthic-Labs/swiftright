// swift-tools-version: 6.0
// SR0-C negative fixtures. Each NegXxx target must FAIL to compile against the SR0 slice
// (probes/sr0-s/fresh-runtime, module SwiftRightRuntime). PositiveControl must compile.
import PackageDescription

let slice: Target.Dependency = .product(name: "SwiftRightRuntime", package: "fresh-runtime")
let mode: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "negative-fixtures",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../sr0-s/fresh-runtime")],
    targets: [
        .target(name: "PositiveControl", dependencies: [slice], swiftSettings: mode),
        .target(name: "NegOnReceive", dependencies: [slice], swiftSettings: mode),
        .target(name: "NegObservableObject", dependencies: [slice], swiftSettings: mode),
        .target(name: "NegTimerPublish", dependencies: [slice], swiftSettings: mode),
    ]
)
