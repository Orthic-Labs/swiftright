// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftHost",
    targets: [
        .target(name: "CDispatchPrivate", path: "Sources/CDispatchPrivate"),
        .systemLibrary(name: "CSwiftRightRender", path: "Sources/CSwiftRightRender"),
        .executableTarget(
            name: "SwiftHost",
            dependencies: ["CDispatchPrivate", "CSwiftRightRender"],
            path: "Sources/SwiftHost"
        ),
    ]
)
