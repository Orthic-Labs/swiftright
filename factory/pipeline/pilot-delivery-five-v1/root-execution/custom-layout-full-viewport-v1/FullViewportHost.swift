import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

func argument(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name),
          i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

func rect(_ value: CGRect) -> [String: Double] {
    ["x": value.minX, "y": value.minY, "width": value.width, "height": value.height]
}

@main
struct FullViewportHost {
    @MainActor static func main() throws {
        guard let path = argument("--png"),
              let scaleText = argument("--scale"), let scale = Double(scaleText),
              scale == 2.5,
              path.hasPrefix("/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/")
        else { throw NSError(domain: "FactoryViewport", code: 1) }
        let monoStartNs = DispatchTime.now().uptimeNanoseconds
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // Explicit host context; unchanged witness receives SwiftUI's centered frame.
        let content = Witness_custom_layout()
            .environment(\.colorScheme, .light)
            .frame(width: 320, height: 240, alignment: .center)
            .background(Color.white)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "SwiftRight factory full viewport"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .white
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.setContentSize(NSSize(width: 320, height: 240))
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        defer { window.close() }
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 320, height: 240)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let image = renderer.cgImage, image.width == 800, image.height == 600,
              let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw NSError(domain: "FactoryViewport", code: 2) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "FactoryViewport", code: 3)
        }
        let result: [String: Any] = [
            "kind": "factory-full-viewport-mac-observation-v1", "status": "OBSERVED",
            "monoStartNs": monoStartNs, "monoEndNs": DispatchTime.now().uptimeNanoseconds,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "paintProducer": "Apple SwiftUI ImageRenderer of full NSHostingView root content",
            "viewportPoints": [320, 240], "hostBoundsPoints": rect(host.bounds),
            "windowContentLayoutRectPoints": rect(window.contentLayoutRect),
            "captureScale": scale, "screenBackingScale": window.backingScaleFactor,
            "imagePixels": [image.width, image.height], "pngPath": path,
            "hostAlignment": "center", "hostBackground": "explicit opaque white",
            "permissionRequests": false, "screenCaptureAttempted": false,
            "accessibilityAttempted": false, "inputActions": 0, "qualified": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
