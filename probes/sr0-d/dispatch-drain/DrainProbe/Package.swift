// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DrainProbe",
    targets: [
        .target(name: "CDispatchPrivate", path: "Sources/CDispatchPrivate"),
        .executableTarget(
            name: "DrainProbe",
            dependencies: ["CDispatchPrivate"],
            path: "Sources/DrainProbe"
        ),
    ]
)
