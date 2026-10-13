import AppKit
import ObjectiveC

// F3 / block 17, Mac side: observe the alerts SwiftUI presents WITHOUT showing anything.
// SwiftUI presents `.alert` and `.confirmationDialog` through NSAlert (`beginSheetModalForWindow:completionHandler:`), which orders a panel onto a display.
// A capture host that must never put a window on a screen replaces the presenting methods with a recorder for the life of its process (a capture-tool technique,
// not product code): the NSAlert SwiftUI built, with its title, informative text, buttons (order, key equivalents, destructive flag) and the completion handler,
// is kept; nothing is ordered in (`orderWindow:relativeTo:` of every window of the process is a no-op as well). `press(_:)` calls the completion handler with
// the button's response, as AppKit does when a button is clicked, so SwiftUI runs the action and resets the binding exactly as it would.
// Measured on macOS 27 / SwiftUI: an alert presented from a never-shown window DOES present (the window is ordered in and a sheet panel appears on screen), which is
// why the hooks exist; an off-screen frame does not help (AppKit puts the panel on a display when its parent is off-screen).

enum AlertHooks {
    nonisolated(unsafe) static var captured: [(alert: NSAlert, complete: (Int) -> Void)] = []

    @MainActor static func install() {
        func replace(_ cls: AnyClass, _ name: String, _ imp: Any) {
            guard let m = class_getInstanceMethod(cls, NSSelectorFromString(name)) else { fputs("AlertHooks: method \(name) is missing\n", stderr); exit(4) }
            method_setImplementation(m, imp_implementationWithBlock(imp))
        }
        func keep(_ alert: NSAlert, _ handler: Any?) {
            var complete: (Int) -> Void = { _ in }
            if let handler { complete = unsafeBitCast(handler as AnyObject, to: (@convention(block) (Int) -> Void).self) }
            captured.append((alert, complete))
        }
        replace(NSAlert.self, "beginSheetModalForWindow:completionHandler:", { (a: NSAlert, w: NSWindow, h: Any?) in keep(a, h) } as @convention(block) (NSAlert, NSWindow, Any?) -> Void)
        replace(NSAlert.self, "_beginWithCompletionHandler:", { (a: NSAlert, h: Any?) in keep(a, h) } as @convention(block) (NSAlert, Any?) -> Void)
        replace(NSAlert.self, "beginSheetModalForWindow:modalDelegate:didEndSelector:contextInfo:", { (a: NSAlert, w: NSWindow, d: Any?, s: Selector?, c: UnsafeMutableRawPointer?) in keep(a, nil) } as @convention(block) (NSAlert, NSWindow, Any?, Selector?, UnsafeMutableRawPointer?) -> Void)
        replace(NSAlert.self, "runModal", { (a: NSAlert) -> Int in keep(a, nil); return 0 } as @convention(block) (NSAlert) -> Int)
        replace(NSWindow.self, "orderWindow:relativeTo:", { (w: NSWindow, mode: Int, n: Int) in } as @convention(block) (NSWindow, Int, Int) -> Void)
        replace(NSWindow.self, "_beginSheet:completionHandler:isCritical:", { (w: NSWindow, sheet: NSWindow, h: Any?, c: Bool) in } as @convention(block) (NSWindow, NSWindow, Any?, Bool) -> Void)
    }

    /// Aborts the process if any window of it is visible on a display (nothing may ever be).
    @MainActor static func assertNothingVisible() {
        for w in NSApp.windows where w.isVisible && NSScreen.screens.contains(where: { $0.frame.intersects(w.frame) }) {
            fputs("AlertHooks: a window reached a display (\(type(of: w))); aborting\n", stderr); w.orderOut(nil); exit(3)
        }
    }

    /// Clicks button `index` (display order) of the first presented alert: SwiftUI gets the completion callback, runs the action and resets the binding.
    @MainActor static func press(_ index: Int) {
        guard let first = captured.first else { return }
        captured.removeFirst()
        first.complete(1000 + index)   // NSAlertFirstButtonReturn + index
    }

    /// The alert as a window record for `pair_semantic_report.py`: title = the alert's message text (Windows: the dialog title), then the informative text and the buttons
    /// in the order AppKit shows them left to right as listed (first = rightmost), each with its default (Return), cancel (Escape) and destructive flags.
    @MainActor static func record(_ alert: NSAlert) -> [String: Any] {
        var kids: [[String: Any]] = []
        if !alert.informativeText.isEmpty { kids.append(["role": "AXStaticText", "value": alert.informativeText, "enabled": true, "focus": false, "children": [Any]()]) }
        for b in alert.buttons {
            kids.append(["role": "AXButton", "name": b.title, "enabled": b.isEnabled, "focus": false, "default": b.keyEquivalent == "\r", "cancel": b.keyEquivalent == "\u{1B}",
                         "destructive": b.hasDestructiveAction, "children": [Any]()])
        }
        let tree: [String: Any] = ["role": "AXWindow", "subrole": "AXDialog", "name": alert.messageText, "enabled": true, "focus": true, "children": kids]
        return ["main": false, "kind": "alert", "title": alert.messageText, "tree": tree]
    }

    /// `AXDump.write` plus a window record for every alert that is currently presented (and not yet pressed).
    @MainActor static func writeDump(main: NSWindow, scale: Double, to path: String) throws {
        var doc = AXDump.dump(main: main, scale: scale)
        doc["windows"] = ((doc["windows"] as? [[String: Any]]) ?? []) + captured.map { record($0.alert) }
        try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
    }
}
