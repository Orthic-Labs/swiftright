import AppKit
import ApplicationServices
import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

// Adapter instrumentation belongs to host, never changes generated witness source.
final class HostObservations: @unchecked Sendable {
    var proposals: [[String: Any]] = []
    var placements: [[String: Any]] = []
    var text: [[String: Any]] = []
    var fontResource: [String: Any] = [:]
}
let observed = HostObservations()
struct MeasureRoot: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        observed.proposals.append(["proposal": ["width": proposal.width as Any? ?? NSNull(), "height": proposal.height as Any? ?? NSNull()], "size": ["width": size.width, "height": size.height]])
        return size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: proposal) }
        observed.placements.append(["x": bounds.minX, "y": bounds.minY, "width": bounds.width, "height": bounds.height])
    }
}
struct MeasureText: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for (lineIndex, line) in layout.enumerated() {
            for (runIndex, run) in line.enumerated() {
                let b = run.typographicBounds
                observed.text.append(["line": lineIndex, "run": runIndex, "width": b.width, "ascent": b.ascent, "descent": b.descent, "leading": b.leading])
                context.draw(run)
            }
        }
    }
}
func value(_ key: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}
func rectangle(_ rect: CGRect) -> [String: Double] {
    ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
}
func emit(_ object: [String: Any]) throws {
    var object = object
    if !observed.fontResource.isEmpty { object["registeredFontResource"] = observed.fontResource }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
@MainActor
func content(instrumented: Bool) -> AnyView {
    let base = AnyView(Witness_disabled().environment(\.colorScheme, value("--scheme") == "dark" ? .dark : .light))
    if instrumented { return AnyView(MeasureRoot { base }.textRenderer(MeasureText())) }
    return base
}
@main
struct CaptureHost {
    @MainActor static func main() throws {
        if CommandLine.arguments.contains("--preflight") {
            let systemFont = CTFontCreateWithName(".AppleSystemUIFont" as CFString, 16, nil)
            try emit(["axTrusted": AXIsProcessTrusted(), "screenCaptureGranted": CGPreflightScreenCaptureAccess(), "permissionRequests": false, "pid": ProcessInfo.processInfo.processIdentifier,
                      "display": ["mainDisplayPixels": ["width": CGDisplayPixelsWide(CGMainDisplayID()), "height": CGDisplayPixelsHigh(CGMainDisplayID())], "mainDisplayBoundsPoints": rectangle(CGDisplayBounds(CGMainDisplayID())), "mainScreenBackingScaleFactor": NSScreen.main?.backingScaleFactor as Any? ?? NSNull()],
                      "fontInventory": ["families": NSFontManager.shared.availableFontFamilies.sorted(), "systemControl": ["postScriptName": CTFontCopyPostScriptName(systemFont), "family": CTFontCopyFamilyName(systemFont), "size": CTFontGetSize(systemFont), "unitsPerEm": CTFontGetUnitsPerEm(systemFont)]]])
            return
        }
        var registeredURL: URL?
        if let fontPath = value("--font-resource") {
            let url = URL(fileURLWithPath: fontPath).standardizedFileURL.resolvingSymlinksInPath()
            guard url.path.hasPrefix("/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/"), let expectedHash = value("--font-hash"), let expectedPS = value("--font-postscript") else { throw NSError(domain: "F5Font", code: 1) }
            let data = try Data(contentsOf: url)
            let hash = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hash == expectedHash else { throw NSError(domain: "F5Font", code: 2) }
            var error: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else { throw error?.takeRetainedValue() as Error? ?? NSError(domain: "F5Font", code: 3) }
            registeredURL = url
            let font = CTFontCreateWithName(expectedPS as CFString, 18, nil)
            let actualPS = CTFontCopyPostScriptName(font) as String
            guard actualPS == expectedPS, let descriptorURL = CTFontDescriptorCopyAttribute(CTFontCopyFontDescriptor(font), kCTFontURLAttribute) as? URL, descriptorURL.standardizedFileURL.resolvingSymlinksInPath() == url else { throw NSError(domain: "F5Font", code: 4) }
            observed.fontResource = ["scope": "process-only CoreText registration; provider identity distinct from TextRenderer glyph font", "resourcePath": url.path, "resourceHash": hash, "postScriptName": actualPS, "family": CTFontCopyFamilyName(font), "fontDescriptorURL": descriptorURL.path, "unitsPerEm": CTFontGetUnitsPerEm(font), "size": CTFontGetSize(font), "ascent": CTFontGetAscent(font), "descent": CTFontGetDescent(font), "leading": CTFontGetLeading(font)]
        }
        defer { if let url = registeredURL { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) } }
        if CommandLine.arguments.contains("--window") || CommandLine.arguments.contains("--f1-cross-interactive") {
            if CommandLine.arguments.contains("--compositor"), !CGPreflightScreenCaptureAccess() {
                try emit(["status": "HELD", "reason": "no-prompt screen permission preflight denied", "permissionRequests": false])
                return
            }
            // Existing signed recorder preflights its own trust before launching this mode.
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 320, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "SwiftRightFactory-" + (value("--case") ?? "witness")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content(instrumented: false))
            window.makeKeyAndOrderFront(nil)
            window.displayIfNeeded()
            if let events = value("--events") {
                try Data("{\"kind\":\"root-appear\",\"source\":\"host-window-display\"}\n".utf8).write(to: URL(fileURLWithPath: events))
            }
            DispatchQueue.global().async {
                while let line = readLine() {
                    if line.contains("quit") { DispatchQueue.main.async { NSApplication.shared.terminate(nil) }; break }
                }
            }
            if CommandLine.arguments.contains("--compositor") {
                guard CGPreflightScreenCaptureAccess() else {
                    try emit(["status": "HELD", "reason": "no-prompt screen permission preflight denied", "permissionRequests": false])
                    window.close()
                    return
                }
                Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(300))
                        let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                        guard let own = shareable.windows.first(where: { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier && $0.windowID == CGWindowID(window.windowNumber) }), let png = value("--png") else { throw NSError(domain: "F5", code: 4) }
                        let filter = SCContentFilter(desktopIndependentWindow: own)
                        let configuration = SCStreamConfiguration()
                        configuration.width = Int(own.frame.width)
                        configuration.height = Int(own.frame.height)
                        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: png) as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw NSError(domain: "F5", code: 5) }
                        CGImageDestinationAddImage(destination, image, nil)
                        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "F5", code: 6) }
                        let bytes = image.dataProvider?.data as Data? ?? Data()
                        let host = window.contentView!
                        let hostMetrics: [String: Any] = ["scope": "actual NSHostingView root geometry; not witness internal Layout callbacks", "boundsPoints": rectangle(host.bounds), "framePoints": rectangle(host.frame), "fittingSizePoints": ["width": host.fittingSize.width, "height": host.fittingSize.height], "windowContentLayoutRectPoints": rectangle(window.contentLayoutRect), "backingScaleFactor": window.backingScaleFactor]
                        try emit(["status": Set(bytes).count > 1 ? "OBSERVED" : "UNOBSERVED", "mode": "own-window-compositor", "pid": ProcessInfo.processInfo.processIdentifier, "windowID": own.windowID, "windowTitle": own.title ?? "", "permissionRequests": false, "witnessHostMetrics": hostMetrics, "image": ["width": image.width, "height": image.height, "scale": 1, "uniqueByteValues": Set(bytes).count]])
                    } catch {
                        try? emit(["status": "HELD", "mode": "own-window-compositor", "reason": String(describing: error), "permissionRequests": false])
                    }
                    window.close()
                    NSApplication.shared.terminate(nil)
                }
            }
            app.run()
            window.close()
            return
        }
        let scale = Double(value("--scale") ?? "1") ?? 1
        let instrumented = !CommandLine.arguments.contains("--plain")
        let start = DispatchTime.now().uptimeNanoseconds
        let renderer = ImageRenderer(content: content(instrumented: instrumented))
        renderer.scale = scale
        guard let image = renderer.cgImage, let path = value("--png") else { throw NSError(domain: "F5", code: 1, userInfo: [NSLocalizedDescriptionKey: "ImageRenderer returned no image or --png missing"]) }
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw NSError(domain: "F5", code: 2) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "F5", code: 3) }
        // Read rendered pixels, reject blank/constant output; image dimensions alone prove little.
        let bytes = image.dataProvider?.data as Data? ?? Data()
        let uniqueBytes = Set(bytes).count
        let font = CTFontCreateWithName(".AppleSystemUIFont" as CFString, 16, nil)
        let end = DispatchTime.now().uptimeNanoseconds
        try emit(["status": uniqueBytes > 1 ? "OBSERVED" : "UNOBSERVED", "mode": "offscreen", "instrumented": instrumented, "pid": ProcessInfo.processInfo.processIdentifier, "monoStartNs": start, "monoEndNs": end,
                  "image": ["width": image.width, "height": image.height, "scale": scale, "bytesPerRow": image.bytesPerRow, "uniqueByteValues": uniqueBytes],
                  "rootLayout": ["proposals": observed.proposals, "placements": observed.placements],
                  "textRendererRuns": observed.text,
                  "fontProviderControl": ["scope": "separate CoreText system-font control; not witness font resolution", "postScriptName": CTFontCopyPostScriptName(font), "family": CTFontCopyFamilyName(font), "size": CTFontGetSize(font)],
                  "permissions": ["axTrusted": AXIsProcessTrusted(), "screenCaptureGranted": CGPreflightScreenCaptureAccess(), "permissionRequests": false],
                  "host": ["os": ProcessInfo.processInfo.operatingSystemVersionString, "arch": "arm64", "mainDisplayPixels": ["width": CGDisplayPixelsWide(CGMainDisplayID()), "height": CGDisplayPixelsHigh(CGMainDisplayID())], "mainDisplayPoints": ["width": CGDisplayBounds(CGMainDisplayID()).width, "height": CGDisplayBounds(CGMainDisplayID()).height]]])
    }
}
