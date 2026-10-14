import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Mac capture host for blocks 6-10 cases (png mode: --plain --scale S --png FILE). Offscreen: an NSHostingView in a never-shown borderless
// window, drawn with cacheDisplay into a bitmap of 320x240 pt * scale. (ImageRenderer renders ScrollView blank, so it is not used here.)
// The witness is the case's own Witness.swift, byte-identical to the Windows package copy; this file only places it centred on white.

func value(_ key: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

@main
struct CaptureHost {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let scale = Double(value("--scale") ?? "1") ?? 1
        guard let path = value("--png") else { throw NSError(domain: "MacHost", code: 1, userInfo: [NSLocalizedDescriptionKey: "--png missing"]) }
        // The reference screen is pinned to a 2x display (decision C11): SwiftUI lays text out for the scale it sees, the attached screen decides otherwise (a headless
        // 1920x1080 at 1x gives a 2 px taller line than a Retina panel). `--display-scale` overrides.
        let displayScale = Double(value("--display-scale") ?? "2") ?? 2
        PinnedScaleWindow.pinned = CGFloat(displayScale)
        let screens = NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))@\($0.backingScaleFactor)x" }.joined(separator: ",")
        print("MAC_ENV os=\(ProcessInfo.processInfo.operatingSystemVersionString) pinnedDisplayScale=\(displayScale) screens=[\(screens)]")
        let root = ZStack(alignment: .center) { Witness_opacity_text() }
            .frame(width: 320, height: 240, alignment: .center)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.displayScale, displayScale)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        let window = PinnedScaleWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(320 * scale), pixelsHigh: Int(240 * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw NSError(domain: "MacHost", code: 2) }
        rep.size = NSSize(width: 320, height: 240)
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "MacHost", code: 3) }
        try png.write(to: URL(fileURLWithPath: path))
        print("{\"status\":\"OBSERVED\",\"mode\":\"offscreen-hosting-view\",\"scale\":\(scale),\"pixels\":[\(rep.pixelsWide),\(rep.pixelsHigh)]}")
    }
}

/// The window reports the pinned backing scale instead of the attached screen's (decision C11): SwiftUI lays text out and settles springs for the scale it sees.
final class PinnedScaleWindow: NSWindow {
    nonisolated(unsafe) static var pinned: CGFloat = 1
    override var backingScaleFactor: CGFloat { Self.pinned }
}
