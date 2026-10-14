import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Mac capture host for the text-input blocks (13 TextField, 14 FocusState, 15 IME). Like blocks-6-10/shared-mac-host the witness is hosted in an NSHostingView
// inside a borderless window, drawn at the capture scale into an 800x600 bitmap, and `--ax FILE` writes the in-process accessibility dump (factory/tools/mac-ax-dump).
// Added here: `--steps JSON` drives the witness with the same step vocabulary as the Windows F2 job (factory/tools/sandbox/README.md), client PIXELS
// converted to points: click {x,y}, key {key, mods}, char {text}, ime {action: compose|commit|cancel, text}, wait {ms}. Events go to the window with
// NSWindow.sendEvent, and `ime` calls NSTextInputClient (setMarkedText / insertText) on the first responder, which is the field editor of the focused field.
//
// A window that is never ordered receives no events, so WHEN `--steps` is given the borderless window is ordered to a frame far off every screen (-30000, -30000) in an
// accessory-policy app (no Dock icon, never activated, never key, no pixel of it is ever on a display). Without `--steps` the window is never ordered
// (nothing at all happens on the Mac), as in blocks 6-10. The window answers the private `hasKeyAppearance` so controls draw active, and reports the capture scale.
// MAC_FACT lines record the field editor (text, selection, marked range) after each step; they are measurements, not gates.
// usage: host --plain --scale 2.5 --png FILE [--ax FILE] [--steps JSON]

func value(_ key: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

let captureScale = CGFloat(Double(value("--scale") ?? "2.5") ?? 2.5)

final class OffscreenWindow: NSWindow {
    @objc(hasKeyAppearance) func hasKeyAppearanceOverride() -> Bool { true }
    override var backingScaleFactor: CGFloat { ScalePin.scale }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor func spin(_ seconds: Double = 0.12) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

struct KeySpec { let code: UInt16; let chars: String }
let namedKeys: [String: KeySpec] = [
    "Tab": KeySpec(code: 48, chars: "\t"), "Enter": KeySpec(code: 36, chars: "\r"), "Escape": KeySpec(code: 53, chars: "\u{1b}"),
    "Space": KeySpec(code: 49, chars: " "), "Backspace": KeySpec(code: 51, chars: "\u{7f}"), "Delete": KeySpec(code: 117, chars: "\u{f728}"),
    "Left": KeySpec(code: 123, chars: "\u{f702}"), "Right": KeySpec(code: 124, chars: "\u{f703}"), "Down": KeySpec(code: 125, chars: "\u{f701}"),
    "Up": KeySpec(code: 126, chars: "\u{f700}"), "Home": KeySpec(code: 115, chars: "\u{f729}"), "End": KeySpec(code: 119, chars: "\u{f72b}"),
]

@MainActor
final class StepRunner {
    let window: NSWindow, host: NSHostingView<AnyView>, height: CGFloat, ax: String?
    init(window: NSWindow, host: NSHostingView<AnyView>, height: CGFloat, ax: String?) { self.window = window; self.host = host; self.height = height; self.ax = ax }

    var client: NSTextInputClient? { window.firstResponder as? NSTextInputClient }

    func fact(_ tag: String) {
        var line = "MAC_FACT step=\(tag)"
        if let tv = window.firstResponder as? NSTextView {
            line += " fieldEditor=1 text=\(tv.string.debugDescription) selection=\(tv.selectedRange().location)+\(tv.selectedRange().length) marked=\(tv.markedRange().location == NSNotFound ? "none" : "\(tv.markedRange().location)+\(tv.markedRange().length)")"
            // The insertion point's x in capture pixels (AppKit draws no caret in a window that is never on a display): firstRect of an empty range at the selection start, screen -> window.
            if let w = tv.window {
                let r = w.convertFromScreen(tv.firstRect(forCharacterRange: NSRange(location: tv.selectedRange().location, length: 0), actualRange: nil))
                line += " caretXpx=\(String(format: "%.2f", Double(r.origin.x * captureScale)))"
            }
        } else { line += " fieldEditor=0 firstResponder=\(type(of: window.firstResponder as Any))" }
        print(line)
    }

    func click(_ x: Double, _ y: Double, count: Int = 1, button: String = "left") {
        let p = NSPoint(x: x / Double(captureScale), y: Double(height) - y / Double(captureScale))
        let down: NSEvent.EventType = button == "right" ? .rightMouseDown : .leftMouseDown, up: NSEvent.EventType = button == "right" ? .rightMouseUp : .leftMouseUp
        for n in 1...max(1, count) {
            for t in [down, up] {
                window.sendEvent(NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: n, pressure: 1)!)
            }
        }
    }

    func key(_ chars: String, code: UInt16, mods: NSEvent.ModifierFlags) {
        for t in [NSEvent.EventType.keyDown, .keyUp] {
            window.sendEvent(NSEvent.keyEvent(with: t, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!)
        }
    }

    func run(_ steps: [[String: Any]]) {
        spin(0.2)
        fact("start")
        for (i, step) in steps.enumerated() {
            let op = step["op"] as? String ?? ""
            switch op {
            case "click": click((step["x"] as? NSNumber)?.doubleValue ?? 0, (step["y"] as? NSNumber)?.doubleValue ?? 0, count: (step["count"] as? Int) ?? 1, button: step["button"] as? String ?? "left")
            case "char":
                for ch in (step["text"] as? String ?? "") { key(String(ch), code: 0, mods: []); spin(0.03) }
            case "key":
                var mods: NSEvent.ModifierFlags = []
                for m in (step["mods"] as? [String] ?? []) { switch m { case "shift": mods.insert(.shift); case "ctrl": mods.insert(.control); case "alt": mods.insert(.option); default: break } }
                let name = step["key"] as? String ?? ""
                if name == "Tab", !(window.firstResponder is NSTextView) {
                    // A window that is never key has no first responder for the Tab event to start from: ask for the key-view step the event would make.
                    if mods.contains(.shift) { window.selectPreviousKeyView(nil) } else { window.selectNextKeyView(nil) }
                } else if name == "Tab", mods.contains(.shift) { key("\u{19}", code: 48, mods: mods) }
                else if let spec = namedKeys[name] { key(spec.chars, code: spec.code, mods: mods) }
                else if name.count == 1 { key(name.lowercased(), code: 0, mods: mods) }
            case "ime":
                let text = step["text"] as? String ?? ""
                let none = NSRange(location: NSNotFound, length: 0)
                switch step["action"] as? String ?? "" {
                case "compose": client?.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0), replacementRange: none)
                case "commit": client?.insertText(text, replacementRange: none)
                case "cancel": client?.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: none)
                default: break
                }
            case "wait": spin(Double((step["ms"] as? NSNumber)?.doubleValue ?? 100) / 1000); continue
            case "dump":
                // the same label convention as the F2 UIA dump (uia-NN-<label>.json) and AlertHooks: ax-NN-<label>.json beside the final dump
                if let ax, let label = step["label"] as? String { try? AXDump.write(main: window, scale: Double(captureScale), to: ax.replacingOccurrences(of: ".json", with: "-\(label).json")) }
                fact("\(i):dump")
                continue
            default: break
            }
            spin()
            fact("\(i):\(op)")
        }
        spin(0.3)
    }
}

/// A SwiftUI `.switch` Toggle (NSSwitch) redraws its knob and track from a display-link animation after a click; a window that is never on a display never
/// ticks it, so the layers keep the state from before the click while `state` and the accessibility value are already new (measured on derived-click-v1:
/// state 0, knob layers still at the "on" x). Flipping a switch's state and restoring it, with a run-loop turn after each, makes SwiftUI redraw it settled.
/// A programmatic change sends no action (one binding setter call per click, counted), so nothing but pixels changes. No-op without switches.
@MainActor func settleSwitches(_ root: NSView) {
    func all(_ v: NSView) -> [NSSwitch] { (v as? NSSwitch).map { [$0] } ?? v.subviews.flatMap(all) }
    for sw in all(root) { let st = sw.state; sw.state = st == .on ? .off : .on; spin(0.2); sw.state = st; spin(0.3) }
}

@MainActor
func capture(_ witness: AnyView, width: CGFloat, height: CGFloat, to path: String, ax: String?) throws {
    if ax != nil { AXDump.enableInProcessAccessibility() }
    let root = AnyView(ZStack(alignment: .topLeading) { witness }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light))
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = OffscreenWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    ScalePin.report(window: window)
    let steps = value("--steps").flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [[String: Any]] }
    if steps != nil {
        NSApp.setActivationPolicy(.accessory)
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderFrontRegardless()
    }
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    spin(0.3)
    if let steps { StepRunner(window: window, host: host, height: height, ax: ax).run(steps); settleSwitches(host) }
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let pixelsWide = Int((width * captureScale).rounded()), pixelsHigh = Int((height * captureScale).rounded())
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw NSError(domain: "MacHost", code: 1) }
    rep.size = host.bounds.size
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw NSError(domain: "MacHost", code: 1) }
    host.displayIgnoringOpacity(host.bounds, in: context)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "MacHost", code: 2) }
    try png.write(to: URL(fileURLWithPath: path))
    if let ax { try AXDump.write(main: window, scale: Double(captureScale), to: ax) }
    print("MAC_CAPTURE \(pixelsWide)x\(pixelsHigh) scale=\(captureScale) png=\(path)")
}

@main
struct MacCaptureHost {
    @MainActor static func main() throws {
        setvbuf(stdout, nil, _IONBF, 0)
        _ = NSApplication.shared
        guard let png = value("--png") else { throw NSError(domain: "MacHost", code: 3, userInfo: [NSLocalizedDescriptionKey: "--png missing"]) }
        try capture(AnyView(Witness_ime_cancel()), width: 320, height: 240, to: png, ax: value("--ax"))
    }
}
