import AppKit
import Darwin
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

private let fixedWidth = CGFloat(320)
private let fixedHeight = CGFloat(240)
private let witnessWidth = CGFloat(32)
private let witnessHeight = CGFloat(32)
private let renderScale = CGFloat(2.5)
private let scratchPrefix = "/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-matched-scale-v1/scratch/"

private func argument(_ key: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: key), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

private func rootRSS(_ phase: String) throws -> [String: Any] {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else {
        throw NSError(domain: "CustomLayoutMacMatchedScaleHost", code: 5,
                      userInfo: [NSLocalizedDescriptionKey: "rootRSS supervisor unavailable"])
    }
    guard info.resident_size <= 1_073_741_824 else {
        throw NSError(domain: "CustomLayoutMacMatchedScaleHost", code: 6,
                      userInfo: [NSLocalizedDescriptionKey: "rootRSS supervisor bound exceeded"])
    }
    return ["phase": phase, "supervisor": "rootRSS",
            "pid": ProcessInfo.processInfo.processIdentifier,
            "status": "observed", "residentBytes": NSNumber(value: info.resident_size)]
}

private func emit(_ object: [String: Any], scratchRoot: String?) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    if let scratchRoot {
        let url = URL(fileURLWithPath: scratchRoot, isDirectory: true).appendingPathComponent("observation.json")
        try FileManager.default.createDirectory(atPath: scratchRoot, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

@main
struct CustomLayoutMacMatchedScaleHost {
    @MainActor static func main() throws {
        let flags = Set(["--preflight", "--observe", "--scratch-root"])
        var index = 1
        while index < CommandLine.arguments.count {
            let item = CommandLine.arguments[index]
            guard flags.contains(item) else {
                throw NSError(domain: "CustomLayoutMacMatchedScaleHost", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "unsupported argument"])
            }
            index += item == "--scratch-root" ? 2 : 1
        }
        guard index == CommandLine.arguments.count else {
            throw NSError(domain: "CustomLayoutMacMatchedScaleHost", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "scratch value missing"])
        }
        let scratchRoot = argument("--scratch-root") ?? scratchPrefix
        guard scratchRoot.hasPrefix(scratchPrefix), !scratchRoot.contains(".."), !scratchRoot.contains("\n") else {
            throw NSError(domain: "CustomLayoutMacMatchedScaleHost", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "scratch path outside internal root"])
        }
        let common: [String: Any] = [
            "permissionRequests": false,
            "screenCapture": false,
            "accessibilityQueries": false,
            "fixedHostPoints": ["width": fixedWidth, "height": fixedHeight],
            "witnessIntrinsicPoints": ["width": witnessWidth, "height": witnessHeight],
            "renderScale": renderScale,
            "expectedPixelSize": ["width": Int(fixedWidth * renderScale), "height": Int(fixedHeight * renderScale)],
            "hostBackground": "opaque-white",
            "colorScheme": "light",
            "witness": "Witness_custom_layout",
            "witnessPlacement": "centered-in-fixed-viewport",
            "paintPath": "NSHostingView.layoutSubtreeIfNeeded + ImageRenderer.cgImage"
        ]
        if CommandLine.arguments.contains("--preflight") {
            var result = common
            result["kind"] = "custom-layout-matched-scale-mac-preflight-v1"
            result["rootRSS"] = try rootRSS("preflight")
            try emit(result, scratchRoot: scratchRoot)
            return
        }
        guard CommandLine.arguments.contains("--observe") else {
            throw NSError(domain: "CustomLayoutMacMatchedScaleHost", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "--observe or --preflight required"])
        }
        let root = Witness_custom_layout()
            .fixedSize()
            .frame(width: fixedWidth, height: fixedHeight, alignment: .center)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: fixedWidth, height: fixedHeight)
        host.layoutSubtreeIfNeeded()
        let before = try rootRSS("before-render")
        let renderer = ImageRenderer(content: root)
        renderer.scale = renderScale
        guard let image = renderer.cgImage else {
            throw NSError(domain: "CustomLayoutMacMatchedScaleHost", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "renderer produced no image"])
        }
        let bytes = image.dataProvider?.data as Data? ?? Data()
        let after = try rootRSS("after-render")
        let pngURL = URL(fileURLWithPath: scratchRoot, isDirectory: true)
            .appendingPathComponent("client.png")
        try FileManager.default.createDirectory(at: pngURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            pngURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "CustomLayoutMacMatchedScaleHost", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "PNG destination unavailable"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "CustomLayoutMacMatchedScaleHost", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "PNG finalize failed"])
        }
        var result = common
        result["kind"] = "custom-layout-matched-scale-mac-observation-v1"
        result["status"] = Set(bytes).count > 1 ? "OBSERVED" : "UNOBSERVED"
        result["hostMetrics"] = [
            "bounds": ["x": host.bounds.minX, "y": host.bounds.minY, "width": host.bounds.width, "height": host.bounds.height],
            "frame": ["x": host.frame.minX, "y": host.frame.minY, "width": host.frame.width, "height": host.frame.height],
            "fittingSize": ["width": host.fittingSize.width, "height": host.fittingSize.height],
            "layerContentsScale": host.layer?.contentsScale ?? 0
        ]
        result["image"] = ["width": image.width, "height": image.height,
                            "bytesPerRow": image.bytesPerRow, "uniqueByteValues": Set(bytes).count]
        result["pngPath"] = pngURL.path
        result["rootRSS"] = [before, after]
        try emit(result, scratchRoot: scratchRoot)
    }
}
