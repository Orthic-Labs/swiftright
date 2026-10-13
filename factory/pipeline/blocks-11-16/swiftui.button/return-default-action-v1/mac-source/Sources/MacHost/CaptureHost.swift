import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Mac capture host for blocks 11-16 (lane A: Button, List). Like blocks-17-20/shared-mac-host: the witness is hosted in an NSHostingView inside a borderless
// window that is NEVER ordered onto a screen (nothing appears, nothing takes focus, no permission is asked), drawn at the capture scale into an 800x600 bitmap.
// Interaction (`--steps JSON|FILE`, the same step list the Windows Sandbox job takes, client pixels): `click` presses the Button under the point (an
// accessibility press, because AppKit drops synthetic mouse events for a window that is not on screen: measured) or selects the table row under it; `key`
// sends a key-down to the table when the witness has one (Up/Down/Delete/Return), else to the window's key equivalents (Return/Escape/characters, as a
// Button's keyboardShortcut); `invoke` presses the Button named `name`; `wait`; `dump` writes the in-process accessibility dump `ax-NN-<label>.json`, `shot`
// a PNG `run-NN-<label>.png`. After the steps: the final PNG and (with --ax FILE) the final dump (factory/tools/mac-ax-dump/AXDump.swift).
// `--fit` also prints the witness's NSHostingView.fittingSize (diagnostics).
// usage: host --plain --scale 2.5 --png FILE [--ax FILE] [--steps JSON|FILE]

func value(_ key: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

let captureScale = CGFloat(Double(value("--scale") ?? "2.5") ?? 2.5)

final class OffscreenWindow: NSWindow {
    // AppKit asks the window whether to draw controls active; offscreen there is no activation, so say yes.
    @objc(hasKeyAppearance) func hasKeyAppearanceOverride() -> Bool { true }
    override var backingScaleFactor: CGFloat { captureScale }
    override var canBecomeKey: Bool { true }
}

func pump(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

// Drag-and-drop without a drag: SwiftUI's List reorders through its NSOutlineView data source (`outlineView(_:validateDrop:...)` / `acceptDrop`), which wants a live
// dragging session (`draggingSession(_:willBeginAt:forItems:)` stores state on it) and an NSDraggingInfo. A session cannot be created without showing a drag
// image on screen, so the capture host hands SwiftUI stand-ins (private selectors it sets on the session are provided; the drop is the one a drag would deliver).
final class FakeDragSession: NSObject {
    @objc var localItemObjects: Any?
    @objc var draggingFormation = 0
    @objc var animatesToDestination = false
    @objc var draggingLeader: Any?
    @objc var draggingLocation = NSPoint(x: 100, y: 100)
    @objc var draggingPasteboard: Any?
    @objc var draggingSequenceNumber = 1
    @objc var numberOfValidItemsForDrop = 1
    @objc var draggingLeaderIndex = 0
    @objc var springLoadingHighlight = 0
    @objc var itemCount = 1
}

final class FakeDragInfo: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard, location: NSPoint, window: NSWindow?, source: Any?, writers: [NSPasteboardWriting]
    init(pasteboard: NSPasteboard, location: NSPoint, window: NSWindow?, source: Any?, writers: [NSPasteboardWriting]) {
        self.pasteboard = pasteboard; self.location = location; self.window = window; self.source = source; self.writers = writers
    }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { .every }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { source }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation { get { .default } set {} }
    var animatesToDestination: Bool { get { false } set {} }
    var numberOfValidItemsForDrop: Int { get { 1 } set {} }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        for (i, w) in writers.enumerated() { block(NSDraggingItem(pasteboardWriter: w), i, &stop); if stop.boolValue { break } }
    }
    func resetSpringLoading() {}
}

@MainActor
final class Driver {
    let host: NSView
    let window: NSWindow
    init(host: NSView, window: NSWindow) { self.host = host; self.window = window }

    func settle() { host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); pump(0.15); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() }

    func table() -> NSTableView? {
        func find(_ v: NSView) -> NSTableView? { if let t = v as? NSTableView { return t }; for s in v.subviews { if let f = find(s) { return f } }; return nil }
        return find(host)
    }

    func children(_ o: NSObject) -> [NSObject] {
        if o.responds(to: Selector("accessibilityChildren")), let k = o.perform(Selector("accessibilityChildren"))?.takeUnretainedValue() as? [Any] {
            let objs = k.compactMap { $0 as? NSObject }
            if !objs.isEmpty { return objs }
        }
        return (o as? NSView)?.subviews ?? []
    }

    func role(_ o: NSObject) -> String { o.responds(to: Selector("accessibilityRole")) ? ((o.value(forKey: "accessibilityRole") as? String) ?? "") : "" }
    func label(_ o: NSObject) -> String { o.responds(to: Selector("accessibilityLabel")) ? ((o.value(forKey: "accessibilityLabel") as? String) ?? "") : "" }

    /// The frame of an accessibility element in the host's top-left point space.
    func frame(_ o: NSObject) -> CGRect? {
        guard o.responds(to: Selector("accessibilityFrame")), let r = (o.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue else { return nil }
        let w = window.convertFromScreen(r)
        return CGRect(x: w.origin.x, y: host.bounds.height - (w.origin.y + w.height), width: w.width, height: w.height)
    }

    func buttons(_ o: NSObject, _ out: inout [NSObject], depth: Int = 0) {
        if role(o) == "AXButton" { out.append(o) }
        if depth < 12 { for c in children(o) { buttons(c, &out, depth: depth + 1) } }
    }

    func pressButton(where match: (NSObject) -> Bool) throws {
        var all: [NSObject] = []
        buttons(host, &all)
        guard let b = all.first(where: match) else { throw NSError(domain: "MacHost", code: 6, userInfo: [NSLocalizedDescriptionKey: "no button matches (\(all.count) buttons)"]) }
        // a disabled button refuses the press, as a click on it does nothing
        if b.responds(to: Selector("isAccessibilityEnabled")), (b.value(forKey: "accessibilityEnabled") as? Bool) == false { return }
        guard (b as AnyObject).accessibilityPerformPress() else { throw NSError(domain: "MacHost", code: 7, userInfo: [NSLocalizedDescriptionKey: "press refused"]) }
    }

    func click(px: Double, py: Double, mods: [String]) throws {
        let pt = CGPoint(x: px / Double(captureScale), y: py / Double(captureScale))
        if let tv = table() {
            if window.firstResponder !== tv { _ = window.makeFirstResponder(tv) }   // a click gives the table the keyboard (the selection then paints in the accent colour)
            let inWindow = NSPoint(x: pt.x, y: host.bounds.height - pt.y)
            let local = tv.convert(inWindow, from: nil)
            let row = tv.row(at: local)
            if row >= 0 {
                if mods.contains("cmd") || mods.contains("ctrl") {
                    if tv.isRowSelected(row) { tv.deselectRow(row) } else { tv.selectRowIndexes([row], byExtendingSelection: true) }
                } else if mods.contains("shift"), let last = tv.selectedRowIndexes.last {
                    tv.selectRowIndexes(IndexSet(integersIn: min(last, row)...max(last, row)), byExtendingSelection: false)
                } else { tv.selectRowIndexes([row], byExtendingSelection: false) }
                return
            }
        }
        try pressButton(where: { self.frame($0)?.contains(pt) ?? false })
    }

    /// Drops the selected row `delta` places away (below its neighbour for +1) through the outline view's drag-and-drop data source, as a drag would: the
    /// `onMove` handler gets (offsets, destination) exactly as for a user's drag.
    func moveSelectedRow(in tv: NSTableView, by delta: Int) throws {
        guard let ov = tv as? NSOutlineView, let ds = ov.dataSource else { throw NSError(domain: "MacHost", code: 10, userInfo: [NSLocalizedDescriptionKey: "no outline data source"]) }
        let row = ov.selectedRow
        guard row >= 0, let item = ov.item(atRow: row), let writer = ds.outlineView?(ov, pasteboardWriterForItem: item) else {
            throw NSError(domain: "MacHost", code: 11, userInfo: [NSLocalizedDescriptionKey: "no selected row to move"])
        }
        let pb = NSPasteboard(name: NSPasteboard.Name("swr.move.\(UUID().uuidString)"))
        pb.clearContents(); pb.writeObjects([writer])
        let session = unsafeBitCast(FakeDragSession(), to: NSDraggingSession.self)
        ds.outlineView?(ov, draggingSession: session, willBeginAt: NSPoint(x: 100, y: 100), forItems: [item])
        let info = FakeDragInfo(pasteboard: pb, location: NSPoint(x: 100, y: 100), window: window, source: ov, writers: [writer])
        let childIndex = delta > 0 ? row + delta + 1 : row + delta
        guard ds.outlineView?(ov, validateDrop: info, proposedItem: nil, proposedChildIndex: childIndex) != [] else { throw NSError(domain: "MacHost", code: 12, userInfo: [NSLocalizedDescriptionKey: "drop refused"]) }
        guard ds.outlineView?(ov, acceptDrop: info, item: nil, childIndex: childIndex) == true else { throw NSError(domain: "MacHost", code: 13, userInfo: [NSLocalizedDescriptionKey: "drop not accepted"]) }
    }

    /// The rows of the witness's table as data: index, selected, the text inside the row (its accessibility static texts), its frame in points (top-left origin),
    /// and whether the table holds the keyboard. SwiftUI's own accessibility tree publishes the rows without roles, so the list gate reads the table directly.
    func listDump() -> [String: Any]? {
        guard let tv = table() else { return nil }
        func texts(_ o: NSObject, _ depth: Int = 0) -> [String] {
            var out: [String] = []
            if role(o) == "AXStaticText" { if let v = o.value(forKey: "accessibilityValue") as? String { out.append(v) } }
            if depth < 10 { for c in children(o) { out += texts(c, depth + 1) } }
            return out
        }
        var rows: [[String: Any]] = []
        for r in 0..<tv.numberOfRows {
            let rect = tv.convert(tv.rect(ofRow: r), to: nil)
            let top = host.bounds.height - (rect.origin.y + rect.height)
            var t: [String] = []
            if let cell = tv.view(atColumn: 0, row: r, makeIfNecessary: false) { t = texts(cell) }
            rows.append(["index": r, "selected": tv.isRowSelected(r), "text": t.joined(separator: " "), "frame": [rect.origin.x, top, rect.width, rect.height]])
        }
        return ["rows": rows, "keyboard": window.firstResponder === tv, "selected": Array(tv.selectedRowIndexes)]
    }

    static let keyCodes: [String: (UInt16, String)] = [
        "Down": (125, String(UnicodeScalar(NSDownArrowFunctionKey)!)), "Up": (126, String(UnicodeScalar(NSUpArrowFunctionKey)!)),
        "Left": (123, String(UnicodeScalar(NSLeftArrowFunctionKey)!)), "Right": (124, String(UnicodeScalar(NSRightArrowFunctionKey)!)),
        "Enter": (36, "\r"), "Return": (36, "\r"), "Escape": (53, "\u{1b}"), "Space": (49, " "), "Tab": (48, "\t"),
        "Delete": (51, "\u{7f}"), "Backspace": (51, "\u{7f}"), "Home": (115, String(UnicodeScalar(NSHomeFunctionKey)!)), "End": (119, String(UnicodeScalar(NSEndFunctionKey)!)),
    ]

    func key(_ name: String, mods: [String]) throws {
        var flags: NSEvent.ModifierFlags = []
        if mods.contains("shift") { flags.insert(.shift) }; if mods.contains("ctrl") || mods.contains("cmd") { flags.insert(.command) }; if mods.contains("alt") { flags.insert(.option) }
        let (code, chars): (UInt16, String) = Self.keyCodes[name] ?? (0, name.lowercased())
        let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                  context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        if name == "Tab" { if flags.contains(.shift) { window.selectPreviousKeyView(nil) } else { window.selectNextKeyView(nil) }; return }
        if let tv = table(), name == "PageDown" || name == "PageUp" {
            // PageUp/PageDown: the model route to onMove, as on the Windows host: drop the selected row one place below / above its neighbour through the table's drag-and-drop
            // data source (what a drag does)
            try moveSelectedRow(in: tv, by: name == "PageDown" ? 1 : -1)
            return
        }
        if let tv = table(), ["Down", "Up", "Delete", "Backspace", "Home", "End", "Space", "Return", "Enter"].contains(name) {
            if window.firstResponder !== tv { _ = window.makeFirstResponder(tv) }
            // Delete reaches `deleteBackward:` through the text-input system a key-down goes through (a bare `keyDown` does not run SwiftUI's onDelete)
            if name == "Delete" || name == "Backspace" { tv.interpretKeyEvents([ev]) } else { tv.keyDown(with: ev) }
            return
        }
        if !window.performKeyEquivalent(with: ev) { (window.firstResponder ?? host).keyDown(with: ev) }
    }
}

@MainActor
func runSteps(_ steps: [[String: Any]], driver: Driver, png: String, ax: String?) throws {
    for (i, s) in steps.enumerated() {
        let op = s["op"] as? String ?? ""
        let mods = (s["mods"] as? [String]) ?? []
        do {
            switch op {
            case "click": try driver.click(px: (s["x"] as? NSNumber)?.doubleValue ?? 0, py: (s["y"] as? NSNumber)?.doubleValue ?? 0, mods: mods)
            case "key": try driver.key(s["key"] as? String ?? "", mods: mods)
            case "char": for ch in (s["text"] as? String ?? "") { try driver.key(String(ch), mods: []) }
            case "invoke":
                let name = s["name"] as? String ?? ""
                try driver.pressButton(where: { driver.label($0) == name })
            case "wait": pump(((s["ms"] as? NSNumber)?.doubleValue ?? 0) / 1000)
            case "dump":
                if let ax { try AXDump.write(main: driver.window, scale: Double(captureScale), to: ax.replacingOccurrences(of: ".json", with: "-\(s["label"] as? String ?? "step").json")) }
            case "shot":
                try writePNG(driver, to: png.replacingOccurrences(of: ".png", with: "-\(s["label"] as? String ?? "step").png"))
            default: throw NSError(domain: "MacHost", code: 8, userInfo: [NSLocalizedDescriptionKey: "unknown op \(op)"])
            }
        } catch { throw NSError(domain: "MacHost", code: 9, userInfo: [NSLocalizedDescriptionKey: "step \(i + 1) (\(op)): \(error.localizedDescription)"]) }
        driver.settle()
    }
}

@MainActor
func writePNG(_ driver: Driver, to path: String) throws {
    let host = driver.host
    driver.settle()
    let pixelsWide = Int((host.bounds.width * captureScale).rounded()), pixelsHigh = Int((host.bounds.height * captureScale).rounded())
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw NSError(domain: "MacHost", code: 1) }
    rep.size = host.bounds.size   // points; must be set before the graphics context exists, or drawing is not scaled
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw NSError(domain: "MacHost", code: 1) }
    host.displayIgnoringOpacity(host.bounds, in: context)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "MacHost", code: 2) }
    try png.write(to: URL(fileURLWithPath: path))
}

@MainActor
func capture(_ witness: AnyView, width: CGFloat, height: CGFloat, to path: String, ax: String?) throws {
    AXDump.enableInProcessAccessibility()     // before the hosting view exists (SwiftUI builds its accessibility nodes only then)
    let base = AnyView(ZStack(alignment: .center) { witness }
        .frame(width: width, height: height, alignment: .center)
        .background(Color.white))
    let root = AnyView(base.environment(\.colorScheme, .light))
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = OffscreenWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)      // without an appearance the offscreen window draws nothing
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    pump(0.3)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let driver = Driver(host: host, window: window)
    if CommandLine.arguments.contains("--fit") { print("MAC_FIT \(NSHostingView(rootView: witness).fittingSize)") }
    if let spec = value("--steps") {
        let data = spec.hasPrefix("[") || spec.hasPrefix("{") ? Data(spec.utf8) : try Data(contentsOf: URL(fileURLWithPath: spec))
        let parsed = try JSONSerialization.jsonObject(with: data)
        let steps = (parsed as? [[String: Any]]) ?? ((parsed as? [String: Any])?["steps"] as? [[String: Any]]) ?? []
        try runSteps(steps, driver: driver, png: path, ax: ax)
        pump(0.3)
    }
    try writePNG(driver, to: path)
    if let ax { try AXDump.write(main: window, scale: Double(captureScale), to: ax) }
    if let ax, let dump = driver.listDump() {
        let listPath = ax.replacingOccurrences(of: "/ax-", with: "/list-")
        try JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: listPath))
    }
    print("MAC_CAPTURE \(Int((width * captureScale).rounded()))x\(Int((height * captureScale).rounded())) scale=\(captureScale) appearance=\(window.effectiveAppearance.name.rawValue) png=\(path)")
}

@main
struct MacCaptureHost {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        guard let png = value("--png") else { throw NSError(domain: "MacHost", code: 3, userInfo: [NSLocalizedDescriptionKey: "--png missing"]) }
        try capture(AnyView(Witness_button_return_default()), width: 320, height: 240, to: png, ax: value("--ax"))
    }
}
