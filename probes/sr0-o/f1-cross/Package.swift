// swift-tools-version: 6.0
import PackageDescription

// SR0-O F1 cross-platform trace: Mac AX recorder (launches the F1 fixture, drives it, dumps raw per-step observations)
// and the assembler that turns raw Mac / Windows observations plus in-process events into TraceKit v0 traces.
// The comparator is used unchanged through its own CLI (probes/sr0-o/comparator `sr0o-trace`).
let package = Package(
    name: "f1-cross",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "F1MacRecord", targets: ["F1MacRecord"]),
        .executable(name: "F1Assemble", targets: ["F1Assemble"]),
    ],
    targets: [
        .executableTarget(name: "F1MacRecord"),
        .executableTarget(name: "F1Assemble"),
    ],
    swiftLanguageModes: [.v5]
)
