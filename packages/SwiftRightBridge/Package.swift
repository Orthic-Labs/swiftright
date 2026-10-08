// swift-tools-version:6.0
import PackageDescription

// SwiftRightBridge: Swift side of the SwiftRight renderer C ABI v0.
//
// - CSwiftRight: systemLibrary over render/swiftright-abi/include/swiftright.h (symlink,
//   so the header has one source). NO `link` directive: the renderer DLL is loaded
//   explicitly (LoadLibraryW/GetProcAddress), never bound through the import table.
// - CDispatchPrivate: prototypes for the pinned libdispatch SPI used to drain the main
//   queue on Windows (architecture.md section 6, "Dispatch mechanism"). Only referenced
//   under `#if os(Windows)`.
// - SwiftRightBridge: the Windows implementation sits behind `#if os(Windows)`; the
//   platform-neutral marshalling layer also builds on macOS, where `Bridge.load` throws
//   `.unsupportedPlatform`.
let package = Package(
    name: "SwiftRightBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftRightBridge", targets: ["SwiftRightBridge"]),
    ],
    targets: [
        .systemLibrary(name: "CSwiftRight", path: "Sources/CSwiftRight"),
        .target(name: "CDispatchPrivate", path: "Sources/CDispatchPrivate"),
        .target(
            name: "SwiftRightBridge",
            dependencies: ["CSwiftRight", "CDispatchPrivate"],
            path: "Sources/SwiftRightBridge"
        ),
    ],
    swiftLanguageModes: [.v5]
)
