import AppKit
import CoreText
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
    override var backingScaleFactor: CGFloat { ScalePin.scale }
    override var canBecomeKey: Bool { true }
}

/// Input stand-ins a case's Witness can register (round 6 block 38): AppKit drops synthetic mouse events for a window that is not on screen (measured: window.sendEvent,
/// NSApp.postEvent, NSHostingView.mouseDown / mouseMoved / mouseEntered all leave SwiftUI's gestures and hover untouched), so a witness that needs a pointer on the Mac registers
/// what the pointer would do. `click` and `move` take the point in the Witness's points (the frame the witness lays out in, origin top-left); `leave` takes none.
@MainActor
enum FactoryStandIn {
    static var click: ((CGPoint) -> Void)?
    static var move: ((CGPoint) -> Void)?
    static var leave: (() -> Void)?
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

    func sliders(_ o: NSObject, _ out: inout [NSObject], depth: Int = 0) {
        if role(o) == "AXSlider" { out.append(o) }
        if depth < 12 { for c in children(o) { sliders(c, &out, depth: depth + 1) } }
    }

    func number(_ o: NSObject, _ key: String) -> Double? { o.responds(to: Selector(key)) ? (o.value(forKey: key) as? NSNumber)?.doubleValue : nil }
    func isEnabled(_ o: NSObject) -> Bool { !(o.responds(to: Selector("isAccessibilityEnabled")) && (o.value(forKey: "accessibilityEnabled") as? Bool) == false) }

    /// The slider the keyboard is in (round 6 block 37): the one a click or drag last acted on.
    var focusedSlider: NSObject?

    func sliderAt(_ pt: CGPoint) -> NSObject? {
        var all: [NSObject] = []
        sliders(host, &all)
        return all.first(where: { self.frame($0)?.contains(pt) ?? false })
    }

    /// Where a pointer at `x` puts a slider's value: the thumb's centre follows the pointer (the control's 20 pt thumb travels `width - 20`), less the grab offset of a drag
    /// that began on the thumb. AppKit drops synthetic mouse events for a window that is not on screen (measured), so the value is set through the accessibility value (what
    /// a click or drag ends up doing); a stepped slider snaps it itself (measured: nearest multiple of the step from the lower bound).
    func sliderValue(_ s: NSObject, atX x: Double, grab: Double) -> Double? {
        guard let f = frame(s), let lo = number(s, "accessibilityMinValue"), let hi = number(s, "accessibilityMaxValue") else { return nil }
        let t = min(max((x - grab - Double(f.minX) - 10) / max(1, Double(f.width) - 20), 0), 1)
        return lo + t * (hi - lo)
    }

    func setSliderValue(_ s: NSObject, _ v: Double) {
        _ = s.perform(NSSelectorFromString("setAccessibilityValue:"), with: NSNumber(value: v))
    }

    /// The grab offset of a press at x: from the thumb's centre when the press is on the thumb (the AXValueIndicator child), else 0 (the thumb jumps).
    func sliderGrab(_ s: NSObject, atX x: Double) -> Double {
        guard let thumb = children(s).first, let tf = frame(thumb) else { return 0 }
        let centre = Double(tf.midX)
        return abs(x - centre) <= 10 ? x - centre : 0
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
        if let s = sliderAt(pt) {
            guard isEnabled(s) else { return }
            focusedSlider = s
            if let v = sliderValue(s, atX: Double(pt.x), grab: sliderGrab(s, atX: Double(pt.x))) { setSliderValue(s, v) }
            return
        }
        if let stand = FactoryStandIn.click { stand(CGPoint(x: pt.x - witnessOrigin.x, y: pt.y - witnessOrigin.y)); return }
        try pressButton(where: { self.frame($0)?.contains(pt) ?? false })
    }

    /// The witness's top-left in the host's point space (the witness is a 240 x 200 pt frame centred in the 320 x 240 pt viewport).
    var witnessOrigin: CGPoint { CGPoint(x: (host.bounds.width - 240) / 2, y: (host.bounds.height - 200) / 2) }

    /// A drag on a slider: press at (x0, y0), release at (x1, y1); the value follows the pointer from the grab point (round 6 block 37).
    func drag(from p0: CGPoint, to p1: CGPoint) throws {
        guard let s = sliderAt(p0) else { throw NSError(domain: "MacHost", code: 11, userInfo: [NSLocalizedDescriptionKey: "no slider at the drag start"]) }
        guard isEnabled(s) else { return }
        focusedSlider = s
        let grab = sliderGrab(s, atX: Double(p0.x))
        if let v = sliderValue(s, atX: Double(p1.x), grab: grab) { setSliderValue(s, v) }
    }

    /// An arrow key / Home / End / PageUp / PageDown on the slider that holds the keyboard. The arrows are the accessibility increment and decrement (measured: a tenth of the
    /// range, or the step); the key itself cannot be delivered offscreen (the window is never key), so this is the stand-in.
    func sliderKey(_ name: String) -> Bool {
        guard let s = focusedSlider, isEnabled(s), let lo = number(s, "accessibilityMinValue"), let hi = number(s, "accessibilityMaxValue") else { return false }
        let v = number(s, "accessibilityValue") ?? lo
        switch name {
        case "Left", "Down": _ = (s as AnyObject).accessibilityPerformDecrement?()
        case "Right", "Up": _ = (s as AnyObject).accessibilityPerformIncrement?()
        case "Home": setSliderValue(s, lo)
        case "End": setSliderValue(s, hi)
        case "PageUp", "PageDown":
            // a tenth of the range, never less than one arrow step (one arrow step: what an increment changes)
            _ = (s as AnyObject).accessibilityPerformIncrement?(); let one = (number(s, "accessibilityValue") ?? v) - v
            setSliderValue(s, v)
            let large = max(abs(one), (hi - lo) / 10)
            setSliderValue(s, v + (name == "PageUp" ? large : -large))
        default: return false
        }
        return true
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
        if ["Left", "Right", "Up", "Down", "Home", "End", "PageUp", "PageDown"].contains(name), focusedSlider != nil, sliderKey(name) { return }
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

    // MARK: scroll stand-ins (issue #31 lane L1, measurement of the Mac's scrolling)
    // The offscreen window never receives a real wheel, key or mouse event (see FactoryStandIn), so each scroll step drives the NSScrollView the way the event would and then
    // READS THE RESULT BACK: a step that expects the document to move FAILS (recorded in `scrollFailures`, thrown after the final capture so every later step is still measured)
    // when documentVisibleRect did not move. Every step prints one greppable `MAC_SCROLL` line (mac-run-NN.log). Op: {"op":"scroll","how":...,"label":...}; hows:
    //   to        at: "begin" | "mid" | "end" | points from the top: NSClipView.scroll(to:) + reflectScrolledClipView (what the scroller's action does)
    //   wheel     delta (default -1, negative = down), times (default 1): CGEvent(scrollWheelEvent2Source:units: .line, wheelCount 1, wheel1: delta) -> NSEvent -> NSScrollView.scrollWheel(with:)
    //   action    selector (e.g. "scrollPageDown:"), target "scrollview" (default) | "documentview" | "outline": sent with perform(_:); FAILS when the target does not respond
    //   key       key (PageDown | PageUp | End | Home | Down | Up), target "auto" (default: the outline for a List, else the document view): a real key-down NSEvent (function key,
    //             keyCode 121/116/119/115/125/126) tried in order until the offset moves, the winning route printed as path=: keyDown (window.makeFirstResponder + responder.keyDown(with:)),
    //             interpretKeyEvents, windowSendEvent (window.sendEvent), tryToPerform (the paging selectors up the responder chain from the target, the clip view and the scroll view),
    //             and only as the LAST resort derived: clip scroll(to:) by the amount AppKit would use (viewport less verticalPageScroll; the range end / start for End / Home), printed
    //             status=DERIVED derived=true. A DERIVED line is a recorded value, never evidence that the key was delivered. FAIL when nothing moved.
    //   select    row: selects an outline row and gives the outline the keyboard (does not move)
    //   moveDown  times: NSTableView.moveDown(_:) on the outline (the arrow key's action)
    //   axvalue   value (default 0.5): the vertical NSScroller's accessibility value set in process (accessibilitySetValue:forAttribute: AXValue, then setAccessibilityValue:)
    //   scroller  value (default 0.5): NSScroller.doubleValue = value, then its action sent to its target
    // "expect": "move" (default for to/wheel/action/moveDown/axvalue/scroller, but a `to` whose target equals the current offset expects none) | "any".
    var scrollFailures: [String] = []

    struct ScrollReading {
        var y = 0.0, top = 0.0, doc = 0.0, view = 0.0, scroller = -1.0, axValue = -1.0, knob = -1.0, pageScroll = 0.0, lineScroll = 0.0
        var flipped = true, hasScroller = false
        var insets = NSEdgeInsets()
    }

    func scrollViewFound() -> NSScrollView? {
        func find(_ v: NSView) -> NSScrollView? {
            if let s = v as? NSScrollView, s.documentView != nil { return s }
            for c in v.subviews { if let f = find(c) { return f } }
            return nil
        }
        return find(host)
    }

    func scrollReading(_ sv: NSScrollView) -> ScrollReading {
        var r = ScrollReading()
        let vis = sv.documentVisibleRect
        r.doc = Double(sv.documentView?.frame.height ?? 0)
        r.view = Double(vis.height)
        r.flipped = sv.documentView?.isFlipped ?? true
        r.y = Double(vis.origin.y)
        r.top = r.flipped ? r.y : r.doc - r.y - r.view
        r.insets = sv.contentInsets
        r.pageScroll = Double(sv.verticalPageScroll); r.lineScroll = Double(sv.verticalLineScroll)
        if let sc = sv.verticalScroller {
            r.hasScroller = true
            r.scroller = sc.doubleValue
            r.knob = Double(sc.knobProportion)
            r.axValue = (sc.accessibilityValue() as? NSNumber)?.doubleValue ?? -1
        }
        return r
    }

    /// The scroll range from the top in points: -inset.top ... doc - viewport + inset.bottom.
    func scrollRange(_ sv: NSScrollView) -> (min: Double, max: Double) {
        let r = scrollReading(sv)
        let lo = -Double(sv.contentInsets.top)
        return (lo, max(lo, r.doc - Double(sv.contentView.bounds.height) + Double(sv.contentInsets.bottom)))
    }

    func scrollReport(_ label: String, _ how: String, before: ScrollReading, after a: ScrollReading, expectMove: Bool, note: String, derived: Bool = false) {
        let moved = abs(a.y - before.y) > 0.01
        let ok = !expectMove || moved
        func f(_ v: Double) -> String { String(format: "%.3f", v) }
        let status = !ok ? "FAIL" : (derived && moved ? "DERIVED" : "OK")
        // pageAmount: the documentVisibleRect delta from the top (positive = scrolled down) of this step; verticalPageScroll / verticalLineScroll: the scroll view's own values
        print("MAC_SCROLL label=\(label) how=\(how) status=\(status) moved=\(moved) before=\(f(before.y)) offset=\(f(a.y)) pageAmount=\(f(a.top - before.top)) verticalPageScroll=\(f(a.pageScroll)) verticalLineScroll=\(f(a.lineScroll)) top=\(f(a.top)) contentHeight=\(f(a.doc)) viewportHeight=\(f(a.view)) scrollerValue=\(f(a.scroller)) axValue=\(f(a.axValue)) knobProportion=\(f(a.knob)) hasScroller=\(a.hasScroller) flipped=\(a.flipped) insets=\(a.insets.top),\(a.insets.bottom) selected=\(table()?.selectedRow ?? -1) \(note)")
        if !ok { scrollFailures.append("\(label) (\(how)): documentVisibleRect.origin.y stayed \(f(before.y)) \(note)") }
    }

    /// M5: renders the vertical NSScroller view itself (the whole-window capture draws none) at the capture scale into scroller-NN-<label>.png beside the run png, and prints MAC_SCROLLER.
    func scrollerPNG(_ label: String, png: String) throws {
        guard let sv = scrollViewFound(), let sc = sv.verticalScroller else {
            print("MAC_SCROLLER label=\(label) status=FAIL no vertical scroller"); scrollFailures.append("\(label) (scrollerpng): no vertical scroller"); return
        }
        pump(0.2); host.layoutSubtreeIfNeeded(); sc.needsDisplay = true; sc.displayIfNeeded()
        let w = Int((sc.bounds.width * captureScale).rounded()), h = Int((sc.bounds.height * captureScale).rounded())
        guard w > 0, h > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            print("MAC_SCROLLER label=\(label) status=FAIL empty scroller bounds \(sc.bounds)"); scrollFailures.append("\(label) (scrollerpng): empty scroller bounds"); return
        }
        rep.size = sc.bounds.size   // points, so the drawing is scaled to the capture scale
        sc.cacheDisplay(in: sc.bounds, to: rep)
        let path = png.replacingOccurrences(of: "/run-", with: "/scroller-").replacingOccurrences(of: ".png", with: "-\(label).png")
        guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "MacHost", code: 36) }
        try data.write(to: URL(fileURLWithPath: path))
        func r(_ x: NSRect) -> String { String(format: "%.3f,%.3f,%.3f,%.3f", x.origin.x, x.origin.y, x.width, x.height) }
        print("MAC_SCROLLER label=\(label) status=OK scale=\(captureScale) png=\(path) pixels=\(w)x\(h) frame=\(r(sc.frame)) bounds=\(r(sc.bounds)) knobRect=\(r(sc.rect(for: .knob))) knobSlotRect=\(r(sc.rect(for: .knobSlot))) doubleValue=\(String(format: "%.4f", sc.doubleValue)) knobProportion=\(String(format: "%.4f", Double(sc.knobProportion))) style=\(sc.scrollerStyle.rawValue) controlSize=\(sc.controlSize.rawValue) isHidden=\(sc.isHidden) alpha=\(sc.alphaValue) isFlipped=\(sc.isFlipped) offset=\(String(format: "%.3f", Double(sv.documentVisibleRect.origin.y)))")
    }

    func scrollStep(_ s: [String: Any]) throws {
        let label = s["label"] as? String ?? "step", how = s["how"] as? String ?? ""
        guard let sv = scrollViewFound() else { throw NSError(domain: "MacHost", code: 30, userInfo: [NSLocalizedDescriptionKey: "no NSScrollView under the host"]) }
        let before = scrollReading(sv)
        let anyMove = (s["expect"] as? String) == "any"
        var expectMove = !anyMove
        var note = ""
        var derived = false
        func num(_ k: String, _ d: Double) -> Double { (s[k] as? NSNumber)?.doubleValue ?? d }
        switch how {
        case "to":
            let range = scrollRange(sv)
            var top: Double
            switch s["at"] {
            case let n as NSNumber: top = n.doubleValue
            case let str as String where str == "end": top = range.max
            case let str as String where str == "mid": top = (range.min + range.max) / 2
            default: top = range.min
            }
            top = Swift.min(Swift.max(top, range.min), range.max)
            let y = before.flipped ? top : before.doc - top - Double(sv.contentView.bounds.height)
            if abs(top - before.top) < 0.5 { expectMove = false }
            sv.contentView.scroll(to: NSPoint(x: sv.contentView.bounds.origin.x, y: CGFloat(y)))
            sv.reflectScrolledClipView(sv.contentView)
            note = "targetTop=\(top) range=\(range.min)...\(range.max)"
        case "wheel":
            let delta = Int32(num("delta", -1)), times = Int(num("times", 1))
            for _ in 0..<times {
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0), let ev = NSEvent(cgEvent: cg) else {
                    throw NSError(domain: "MacHost", code: 31, userInfo: [NSLocalizedDescriptionKey: "cannot build the scroll wheel event"])
                }
                sv.scrollWheel(with: ev)
                pump(0.05)
            }
            note = "delta=\(delta) times=\(times)"
        case "action":
            let name = s["selector"] as? String ?? ""
            let target = s["target"] as? String ?? "scrollview"
            let obj: NSObject = target == "documentview" ? (sv.documentView ?? sv) : target == "outline" ? (table() ?? sv) : sv
            let sel = NSSelectorFromString(name)
            let responds = obj.responds(to: sel)
            if responds { _ = obj.perform(sel, with: nil) }
            note = "selector=\(name) target=\(target) responds=\(responds)"
            if !responds { scrollFailures.append("\(label) (action): \(target) does not respond to \(name)") }
        case "key":
            let name = s["key"] as? String ?? "PageDown"
            let keyTable: [String: (UInt16, Int, [String])] = [
                "PageDown": (121, NSPageDownFunctionKey, ["pageDown:", "scrollPageDown:"]), "PageUp": (116, NSPageUpFunctionKey, ["pageUp:", "scrollPageUp:"]),
                "End": (119, NSEndFunctionKey, ["scrollToEndOfDocument:", "moveToEndOfDocument:"]), "Home": (115, NSHomeFunctionKey, ["scrollToBeginningOfDocument:", "moveToBeginningOfDocument:"]),
                "Down": (125, NSDownArrowFunctionKey, ["moveDown:"]), "Up": (126, NSUpArrowFunctionKey, ["moveUp:"]),
            ]
            guard let (code, fkey, sels) = keyTable[name] else { throw NSError(domain: "MacHost", code: 37, userInfo: [NSLocalizedDescriptionKey: "unknown key '\(name)'"]) }
            let chars = String(UnicodeScalar(fkey)!)
            guard let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                            context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) else {
                throw NSError(domain: "MacHost", code: 38, userInfo: [NSLocalizedDescriptionKey: "cannot build the key event"])
            }
            let target = s["target"] as? String ?? "auto"
            let primary: NSResponder = target == "scrollview" ? sv : target == "clipview" ? sv.contentView : (table() ?? sv.documentView ?? sv)
            let moved = { abs(Double(sv.documentVisibleRect.origin.y) - before.y) > 0.01 }
            func settleKey() { pump(0.45); sv.layoutSubtreeIfNeeded() }
            var path = "none", tried: [String] = []
            func attempt(_ p: String, _ body: () -> Void) {
                if path != "none" { return }
                tried.append(p); body(); settleKey()
                if moved() { path = p }
            }
            let firstOK = window.makeFirstResponder(primary)
            attempt("keyDown") { primary.keyDown(with: ev) }
            attempt("interpretKeyEvents") { primary.interpretKeyEvents([ev]) }
            attempt("windowSendEvent") { window.sendEvent(ev) }
            for sel in sels {
                let chain: [(String, NSResponder)] = [("target", primary), ("clipview", sv.contentView), ("scrollview", sv)]
                for (rn, r) in chain {
                    attempt("tryToPerform:\(sel):\(rn)") { _ = r.tryToPerform(NSSelectorFromString(sel), with: nil) }
                }
            }
            if path == "none" {
                // LAST RESORT, a derived value (NOT a delivered key): scroll the clip view by the amount AppKit pages with (viewport less verticalPageScroll), or to the range end / start
                let rd = scrollReading(sv), range = scrollRange(sv)
                var top = rd.top
                switch name {
                case "PageDown": top += Swift.max(rd.view - rd.pageScroll, rd.view / 2)
                case "PageUp": top -= Swift.max(rd.view - rd.pageScroll, rd.view / 2)
                case "End": top = range.max
                case "Home": top = range.min
                case "Down": top += rd.lineScroll
                default: top -= rd.lineScroll
                }
                top = Swift.min(Swift.max(top, range.min), range.max)
                let y = rd.flipped ? top : rd.doc - top - Double(sv.contentView.bounds.height)
                sv.contentView.scroll(to: NSPoint(x: sv.contentView.bounds.origin.x, y: CGFloat(y)))
                sv.reflectScrolledClipView(sv.contentView)
                path = "derived"; derived = true
            }
            note = "key=\(name) keyCode=\(code) target=\(target) firstResponder=\(type(of: window.firstResponder as Any)) madeFirstResponder=\(firstOK) path=\(path) derived=\(derived) tried=\(tried.joined(separator: ">"))"
        case "select":
            guard let tv = table() else { throw NSError(domain: "MacHost", code: 32, userInfo: [NSLocalizedDescriptionKey: "no outline to select in"]) }
            let row = Int(num("row", 0))
            if window.firstResponder !== tv { _ = window.makeFirstResponder(tv) }
            tv.selectRowIndexes([row], byExtendingSelection: false)
            expectMove = false
            note = "row=\(row) selectedNow=\(tv.selectedRow)"
            if tv.selectedRow != row { scrollFailures.append("\(label) (select): row \(row) not selected (\(tv.selectedRow))") }
        case "moveDown":
            guard let tv = table() else { throw NSError(domain: "MacHost", code: 33, userInfo: [NSLocalizedDescriptionKey: "no outline to move in"]) }
            if window.firstResponder !== tv { _ = window.makeFirstResponder(tv) }
            let times = Int(num("times", 1))
            for _ in 0..<times { tv.moveDown(nil); pump(0.05) }
            note = "times=\(times) rows=\(tv.numberOfRows)"
        case "axvalue", "scroller":
            guard let sc = sv.verticalScroller else {
                scrollFailures.append("\(label) (\(how)): the scroll view has no vertical scroller"); print("MAC_SCROLL label=\(label) how=\(how) status=FAIL no vertical scroller"); return
            }
            let v = num("value", 0.5)
            if how == "scroller" {
                sc.doubleValue = v
                if let action = sc.action { _ = sc.sendAction(action, to: sc.target) }
                note = "value=\(v) action=\(sc.action.map { NSStringFromSelector($0) } ?? "nil") target=\(sc.target.map { String(describing: type(of: $0)) } ?? "nil") hitPart=\(sc.hitPart.rawValue)"
            } else {
                var path = "none"
                let first = Selector("accessibilitySetValue:forAttribute:"), second = Selector("setAccessibilityValue:")
                if sc.responds(to: first) {
                    _ = sc.perform(first, with: NSNumber(value: v), with: "AXValue" as NSString); path = "accessibilitySetValue:forAttribute:"
                    pump(0.3); sv.layoutSubtreeIfNeeded()
                    if abs(Double(sv.documentVisibleRect.origin.y) - before.y) < 0.01, sc.responds(to: second) {
                        _ = sc.perform(second, with: NSNumber(value: v)); path += ">setAccessibilityValue:"
                    }
                } else if sc.responds(to: second) {
                    _ = sc.perform(second, with: NSNumber(value: v)); path = "setAccessibilityValue:"
                }
                note = "value=\(v) path=\(path)"
            }
        default:
            throw NSError(domain: "MacHost", code: 34, userInfo: [NSLocalizedDescriptionKey: "unknown scroll how '\(how)'"])
        }
        pump(0.35)
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        scrollReport(label, how, before: before, after: scrollReading(sv), expectMove: expectMove, note: note, derived: derived)
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
            case "drag":
                let sc = Double(captureScale)
                func n(_ k: String) -> Double { (s[k] as? NSNumber)?.doubleValue ?? 0 }
                try driver.drag(from: CGPoint(x: n("x0") / sc, y: n("y0") / sc), to: CGPoint(x: n("x1") / sc, y: n("y1") / sc))
            case "move":
                let sc = Double(captureScale), o = driver.witnessOrigin
                FactoryStandIn.move?(CGPoint(x: ((s["x"] as? NSNumber)?.doubleValue ?? 0) / sc - Double(o.x), y: ((s["y"] as? NSNumber)?.doubleValue ?? 0) / sc - Double(o.y)))
            case "leave": FactoryStandIn.leave?()
            case "char": for ch in (s["text"] as? String ?? "") { try driver.key(String(ch), mods: []) }
            case "invoke":
                let name = s["name"] as? String ?? ""
                try driver.pressButton(where: { driver.label($0) == name })
            case "wait": pump(((s["ms"] as? NSNumber)?.doubleValue ?? 0) / 1000)
            case "scroll": try driver.scrollStep(s)
            case "scrollerpng": try driver.scrollerPNG(s["label"] as? String ?? "step", png: png)
            case "listdump":
                // the outline's row frames after this step: list-NN-<label>.json beside the ax dumps (issue #31); a witness without an outline writes nothing
                if let ax, let dump = driver.listDump() {
                    let p = ax.replacingOccurrences(of: "/ax-", with: "/list-").replacingOccurrences(of: ".json", with: "-\(s["label"] as? String ?? "step").json")
                    try JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: p))
                }
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
    ScalePin.report(window: window)
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
    if !driver.scrollFailures.isEmpty {
        throw NSError(domain: "MacHost", code: 35, userInfo: [NSLocalizedDescriptionKey: "scroll stand-in failed (\(driver.scrollFailures.count)): " + driver.scrollFailures.joined(separator: "; ")])
    }
}

@main
struct MacCaptureHost {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        // Bundled fonts (block swiftui.font-custom): `--fonts a.ttf,b.otf` registers them for this process before the view exists, as the Windows host registers the same bytes through
        // the renderer (ABI 0.7 `swr_font_register`).
        if let list = value("--fonts") {
            for path in list.split(separator: ",") {
                var error: Unmanaged<CFError>?
                guard CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: String(path)) as CFURL, .process, &error) else { throw NSError(domain: "MacHost", code: 20, userInfo: [NSLocalizedDescriptionKey: "font registration failed: \(path)"]) }
            }
        }
        guard let png = value("--png") else { throw NSError(domain: "MacHost", code: 3, userInfo: [NSLocalizedDescriptionKey: "--png missing"]) }
        try capture(AnyView(Witness_sc_scroller_list()), width: 320, height: 240, to: png, ax: value("--ax"))
    }
}
