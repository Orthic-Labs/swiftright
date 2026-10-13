import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Mac capture host for control cases (Toggle, disabled controls). ImageRenderer cannot draw AppKit-backed controls (a switch becomes the
// yellow "prohibited" placeholder), so the witness is hosted in an NSHostingView inside a borderless window that is NEVER ordered onto a
// screen: nothing appears, nothing takes focus, no permission is requested. The window reports key appearance and the capture scale as its
// backing scale, so AppKit draws controls in their active state (accent tint) at that scale. The view is drawn into an RGBA bitmap of
// 320x240 pt at the capture scale and written as a PNG.  usage: host --plain --scale 2.5 --png FILE
// Stamped per case by stamp-mac.py; the witness file is the case's own (byte-identical to the Windows package's).

func value(_ key: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

let captureScale = CGFloat(Double(value("--scale") ?? "2.5") ?? 2.5)

final class OffscreenWindow: NSWindow {
    // AppKit asks the window whether to draw controls active; offscreen there is no activation, so say yes.
    @objc(hasKeyAppearance) func hasKeyAppearanceOverride() -> Bool { true }
    override var backingScaleFactor: CGFloat { captureScale }
}

@MainActor
func capture(_ witness: AnyView, width: CGFloat, height: CGFloat, to path: String) throws {
    let root = AnyView(ZStack(alignment: .topLeading) { witness }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light))
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = OffscreenWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let pixelsWide = Int((width * captureScale).rounded()), pixelsHigh = Int((height * captureScale).rounded())
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw NSError(domain: "MacHost", code: 1) }
    rep.size = host.bounds.size   // points; must be set before the graphics context exists, or drawing is not scaled
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw NSError(domain: "MacHost", code: 1) }
    host.displayIgnoringOpacity(host.bounds, in: context)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "MacHost", code: 2) }
    try png.write(to: URL(fileURLWithPath: path))
    print("MAC_CAPTURE \(pixelsWide)x\(pixelsHigh) scale=\(captureScale) png=\(path)")
}

@main
struct MacCaptureHost {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        guard let png = value("--png") else { throw NSError(domain: "MacHost", code: 3, userInfo: [NSLocalizedDescriptionKey: "--png missing"]) }
        try capture(AnyView(Witness_binding_derived()), width: 320, height: 240, to: png)
    }
}
