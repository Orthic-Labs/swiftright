import AppKit
import CoreGraphics
import Darwin
import Foundation
import SwiftUI

private let fixedWidth = CGFloat(320)
private let fixedHeight = CGFloat(240)
private let scratchPrefix = "/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/scratch/"

private func argument(_ key: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: key),
          index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

private func rectangle(_ rect: CGRect) -> [String: Double] {
    ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
}

private func rootRSS(_ phase: String) throws -> [String: Any] {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size /
                                       MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else {
        throw NSError(domain: "CustomLayoutMacHost", code: 5,
                      userInfo: [NSLocalizedDescriptionKey: "rootRSS supervisor unavailable"])
    }
    guard info.resident_size <= 1_073_741_824 else {
        throw NSError(domain: "CustomLayoutMacHost", code: 6,
                      userInfo: [NSLocalizedDescriptionKey: "rootRSS supervisor bound exceeded"])
    }
    return ["phase": phase,
            "supervisor": "rootRSS",
            "pid": ProcessInfo.processInfo.processIdentifier,
            "status": "observed",
            "residentBytes": NSNumber(value: info.resident_size)]
}

private func emit(_ object: [String: Any], scratchRoot: String?) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    let text = String(decoding: data, as: UTF8.self)
    print(text)
    if let scratchRoot {
        let url = URL(fileURLWithPath: scratchRoot, isDirectory: true)
            .appendingPathComponent("observation.json")
        try FileManager.default.createDirectory(atPath: scratchRoot,
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

@main
struct CustomLayoutMacHost {
    @MainActor static func main() throws {
        let flags = Set(["--preflight", "--observe", "--scratch-root"])
        var index = 1
        while index < CommandLine.arguments.count {
            let item = CommandLine.arguments[index]
            guard flags.contains(item) else {
                throw NSError(domain: "CustomLayoutMacHost", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "unsupported argument"])
            }
            index += item == "--scratch-root" ? 2 : 1
        }
        guard index == CommandLine.arguments.count else {
            throw NSError(domain: "CustomLayoutMacHost", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "scratch value missing"])
        }
        let scratchRoot = argument("--scratch-root") ?? scratchPrefix
        guard scratchRoot.hasPrefix(scratchPrefix),
              !scratchRoot.contains(".."), !scratchRoot.contains("\n") else {
            throw NSError(domain: "CustomLayoutMacHost", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "scratch path outside internal root"])
        }
        if CommandLine.arguments.contains("--preflight") {
            try emit(["kind": "custom-layout-mac-preflight-v1",
                      "permissionRequests": false,
                      "axTrusted": AXIsProcessTrusted(),
                      "screenCaptureGranted": CGPreflightScreenCaptureAccess(),
                      "fixedHostPoints": ["width": fixedWidth, "height": fixedHeight],
                      "rootRSS": try rootRSS("preflight")], scratchRoot: scratchRoot)
            return
        }
        guard CommandLine.arguments.contains("--observe") else {
            throw NSError(domain: "CustomLayoutMacHost", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "--observe or --preflight required"])
        }
        let root = Witness_custom_layout()
            .frame(width: fixedWidth, height: fixedHeight, alignment: .topLeading)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: fixedWidth, height: fixedHeight)
        host.layoutSubtreeIfNeeded()
        let before = try rootRSS("before-render")
        let renderer = ImageRenderer(content: root)
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            throw NSError(domain: "CustomLayoutMacHost", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "renderer produced no image"])
        }
        let bytes = image.dataProvider?.data as Data? ?? Data()
        let after = try rootRSS("after-render")
        try emit(["kind": "custom-layout-mac-observation-v1",
                  "status": Set(bytes).count > 1 ? "OBSERVED" : "UNOBSERVED",
                  "permissionRequests": false,
                  "fixedHostPoints": ["width": fixedWidth, "height": fixedHeight],
                  "hostMetrics": ["bounds": rectangle(host.bounds),
                                  "frame": rectangle(host.frame),
                                  "fittingSize": ["width": host.fittingSize.width,
                                                  "height": host.fittingSize.height]],
                  "image": ["width": image.width, "height": image.height,
                            "bytesPerRow": image.bytesPerRow,
                            "uniqueByteValues": Set(bytes).count],
                  "rootRSS": [before, after]], scratchRoot: scratchRoot)
    }
}
