import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Mac capture host for blocks 17-20 (alert, colour scheme). Like blocks-6-10/shared-mac-host: the witness is hosted in an NSHostingView inside a borderless
// window that is NEVER ordered onto a screen (nothing appears, nothing takes focus, no permission is asked), drawn at the capture scale into an 800x600 bitmap.
// Added here: the window appearance (aqua | darkAqua | none) and the root colour scheme (light | dark | none) are stamped per case, so a case chooses whether the
// host or the witness (`.preferredColorScheme`, `.environment(\.colorScheme, _)`) decides; and `--ax FILE` writes the in-process accessibility dump of every
// window of the process (factory/tools/mac-ax-dump/AXDump.swift) for the semantic comparator.
// Alert cases (`yes` = yes): SwiftUI's `.alert` / `.confirmationDialog` are observed through factory/tools/mac-ax-dump/AlertHooks.swift without presenting anything
// (an NSAlert panel would be ordered onto a display otherwise). `--ax FILE` then also writes FILE-with-"-open" (before any press: the presented alert as a window
// record) and `--press K` clicks button K (display order) of the first presented alert, as AppKit does, before the PNG and the final dump are taken.
// usage: host --plain --scale 2.5 --png FILE [--ax FILE] [--press K]

func value(_ key: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

let captureScale = CGFloat(Double(value("--scale") ?? "2.5") ?? 2.5)

final class OffscreenWindow: NSWindow {
    // AppKit asks the window whether to draw controls active; offscreen there is no activation, so say yes.
    @objc(hasKeyAppearance) func hasKeyAppearanceOverride() -> Bool { true }
    override var backingScaleFactor: CGFloat { ScalePin.scale }
}

@MainActor
func capture(_ witness: AnyView, width: CGFloat, height: CGFloat, to path: String, ax: String?) throws {
    let alerts = "yes" == "yes"
    if ax != nil { AXDump.enableInProcessAccessibility() }
    if alerts { AlertHooks.install() }
    let base = AnyView(ZStack(alignment: .topLeading) { witness }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color.white))
    let root: AnyView = "light" == "none" ? base : AnyView(base.environment(\.colorScheme, "light" == "dark" ? .dark : .light))
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = OffscreenWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    if "aqua" != "none" { window.appearance = NSAppearance(named: "aqua" == "darkAqua" ? .darkAqua : .aqua) }
    window.contentView = host
    ScalePin.report(window: window)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    if alerts {
        AlertHooks.assertNothingVisible()
        if let ax { try AlertHooks.writeDump(main: window, scale: Double(captureScale), to: ax.replacingOccurrences(of: ".json", with: "-open.json")) }
        if let press = value("--press").flatMap({ Int($0) }) {
            guard !AlertHooks.captured.isEmpty else { throw NSError(domain: "MacHost", code: 5, userInfo: [NSLocalizedDescriptionKey: "--press with no presented alert"]) }
            AlertHooks.press(press)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
        }
        AlertHooks.assertNothingVisible()
    }
    let pixelsWide = Int((width * captureScale).rounded()), pixelsHigh = Int((height * captureScale).rounded())
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw NSError(domain: "MacHost", code: 1) }
    rep.size = host.bounds.size   // points; must be set before the graphics context exists, or drawing is not scaled
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw NSError(domain: "MacHost", code: 1) }
    host.displayIgnoringOpacity(host.bounds, in: context)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "MacHost", code: 2) }
    try png.write(to: URL(fileURLWithPath: path))
    if let ax { if alerts { try AlertHooks.writeDump(main: window, scale: Double(captureScale), to: ax) } else { try AXDump.write(main: window, scale: Double(captureScale), to: ax) } }
    print("MAC_CAPTURE \(pixelsWide)x\(pixelsHigh) scale=\(captureScale) appearance=\(window.effectiveAppearance.name.rawValue) png=\(path)")
}

@main
struct MacCaptureHost {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        guard let png = value("--png") else { throw NSError(domain: "MacHost", code: 3, userInfo: [NSLocalizedDescriptionKey: "--png missing"]) }
        try capture(AnyView(Witness_alert_confirm_delete()), width: 320, height: 240, to: png, ax: value("--ax"))
    }
}
