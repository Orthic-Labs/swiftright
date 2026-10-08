// swift-tools-version: 6.0
import PackageDescription

// SR0-O Windows UIA recorder + Mac/Windows trace compare CLI.
// The comparator is reused as a path dependency (not edited); Windows normalizer extensions live in UIAKit.
let package = Package(
    name: "uia-recorder",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "UIARecorder", targets: ["UIARecorder"]),
        .executable(name: "UIACompare", targets: ["UIACompare"]),
    ],
    dependencies: [
        .package(path: "../comparator"),
    ],
    targets: [
        // Header-only COM/Win32 shim: UIAutomationClient.h is not in Swift's WinSDK module map.
        .target(name: "CUIA"),
        .target(
            name: "UIAKit",
            dependencies: [
                .target(name: "CUIA", condition: .when(platforms: [.windows])),
            ],
            linkerSettings: [
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                .linkedLibrary("oleaut32", .when(platforms: [.windows])),
                .linkedLibrary("user32", .when(platforms: [.windows])),
            ]
        ),
        .executableTarget(name: "UIARecorder", dependencies: ["UIAKit"]),
        .executableTarget(name: "UIACompare", dependencies: [.product(name: "TraceKit", package: "comparator")]),
        .testTarget(name: "UIAKitTests", dependencies: ["UIAKit", .product(name: "TraceKit", package: "comparator")]),
    ],
    swiftLanguageModes: [.v5]
)
