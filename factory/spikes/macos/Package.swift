// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacCaptureSpike",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "mac-capture-spike", targets: ["MacCaptureSpike"]),
        .executable(name: "mac-capture-ax-client", targets: ["MacCaptureAXClient"])
    ],
    targets: [
        .executableTarget(name: "MacCaptureAXClient", linkerSettings: [.linkedFramework("ApplicationServices")]),
        .executableTarget(
            name: "MacCaptureSpike",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit")
            ]
        )
    ]
)
