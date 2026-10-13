import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Mac capture host for blocks 17-20 (alert, colour scheme). Like blocks-6-10/shared-mac-host: the witness is hosted in an NSHostingView inside a borderless
// window that is NEVER ordered onto a screen (nothing appears, nothing takes focus, no permission is asked), drawn at the capture scale into an 800x600 bitmap.
// Added here: the window appearance (aqua | darkAqua | none) and the root colour scheme (light | dark | none) are stamped per case, so a case chooses whether the
// host or the witness (`.preferredColorScheme`, `.environment(\.colorScheme, _)`) decides; and `--ax FILE` writes the in-process accessibility dump of every
// window of the process (factory/tools/mac-ax-dump/AXDump.swift) for the semantic comparator.
// usage: host --plain --scale 2.5 --png FILE [--ax FILE]

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
func capture(_ witness: AnyView, width: CGFloat, height: CGFloat, to path: String, ax: String?) throws {
    if ax != nil { AXDump.enableInProcessAccessibility() }
    let base = AnyView(ZStack(alignment: .topLeading) { witness }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color.white))
    let root: AnyView = "@@SCHEME@@" == "none" ? base : AnyView(base.environment(\.colorScheme, "@@SCHEME@@" == "dark" ? .dark : .light))
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = OffscreenWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    if "@@APPEARANCE@@" != "none" { window.appearance = NSAppearance(named: "@@APPEARANCE@@" == "darkAqua" ? .darkAqua : .aqua) }
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(@@SETTLE@@))
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
    if let ax { try AXDump.write(main: window, scale: Double(captureScale), to: ax) }
    print("MAC_CAPTURE \(pixelsWide)x\(pixelsHigh) scale=\(captureScale) appearance=\(window.effectiveAppearance.name.rawValue) png=\(path)")
}

@main
struct MacCaptureHost {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        guard let png = value("--png") else { throw NSError(domain: "MacHost", code: 3, userInfo: [NSLocalizedDescriptionKey: "--png missing"]) }
        try capture(AnyView(@@WITNESS@@), width: 320, height: 240, to: png, ax: value("--ax"))
    }
}
