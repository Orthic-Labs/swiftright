import AppKit

// F3 Mac side: an IN-PROCESS dump of the accessibility tree of every window of this process (NSApp.windows, their sheets and child windows).
// It uses the NSAccessibility protocol methods of the live objects (NSView, SwiftUI's accessibility elements, NSAlert's views), never the AX client API
// (AXUIElement), so no other process is queried and no Accessibility/TCC permission is asked. Nothing is ordered onto a screen by this file.
// Output JSON (read by factory/tools/pair_semantic_report.py):
//   { "scale": S, "focusedElement": {name, role}?, "windows": [ { "main": Bool, "kind": "window|sheet|panel|alert", "title": "...", "frame": [x,y,w,h],
//       "tree": { role, subrole, name, value, enabled, focus, id, bounds: [x,y,w,h] points relative to the window's content origin, top-left, children: [...] } } ] }

enum AXDump {
    /// SwiftUI builds its accessibility nodes only when an assistive client has switched the process to enhanced accessibility. An AX client does this by setting
    /// AXEnhancedUserInterface / AXManualAccessibility on the application element; the process can set the same two attributes on ITSELF. Call this BEFORE the hosting
    /// view is created (measured: without it the hosting view has no accessibility children). Nothing is asked of the user and no other process is involved.
    @MainActor static func enableInProcessAccessibility() {
        let set = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            _ = NSApp.perform(set, with: NSNumber(value: true), with: attribute as NSString)
        }
    }

    @MainActor static func string(_ any: Any?) -> String? {
        switch any {
        case nil: return nil
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let a as NSAttributedString: return a.string
        default: return "\(any!)"
        }
    }

    @MainActor static func number(_ any: Any?) -> Any? {
        if let n = any as? NSNumber { return n }
        if let s = any as? String { return s }
        if let a = any as? NSAttributedString { return a.string }
        return nil
    }

    /// The accessibility getters are optional protocol requirements, so they are read through KVC after a `responds(to:)` check (works for NSView, NSAccessibilityElement and SwiftUI's own element classes).
    @MainActor static func get(_ object: NSObject, _ key: String, getter: String? = nil) -> Any? {
        guard object.responds(to: Selector(getter ?? key)) else { return nil }
        return object.value(forKey: key)
    }

    @MainActor static func children(of object: NSObject) -> [NSObject] {
        if object.responds(to: Selector("accessibilityChildren")), let kids = object.perform(Selector("accessibilityChildren"))?.takeUnretainedValue() as? [Any] {
            let objs = kids.compactMap { $0 as? NSObject }
            if !objs.isEmpty { return objs }
        }
        if let view = object as? NSView { return view.subviews }
        return []
    }

    @MainActor static func node(_ object: NSObject, origin: NSPoint, height: CGFloat, depth: Int, seen: inout Set<ObjectIdentifier>) -> [String: Any] {
        var d: [String: Any] = [:]
        d["role"] = string(get(object, "accessibilityRole")) ?? (object is NSView ? "AXGroup" : "AXUnknown")
        if let sub = string(get(object, "accessibilitySubrole")) { d["subrole"] = sub }
        let label = string(get(object, "accessibilityLabel")) ?? string(get(object, "accessibilityTitle"))
        if let label, !label.isEmpty { d["name"] = label }
        if let v = number(get(object, "accessibilityValue")) { d["value"] = v }
        d["enabled"] = (get(object, "accessibilityEnabled", getter: "isAccessibilityEnabled") as? Bool) ?? true
        d["focus"] = (get(object, "accessibilityFocused", getter: "isAccessibilityFocused") as? Bool) ?? false
        if let id = string(get(object, "accessibilityIdentifier")), !id.isEmpty { d["id"] = id }
        if let f = (get(object, "accessibilityFrame") as? NSValue)?.rectValue, f != .zero {
            d["bounds"] = [Double(f.minX - origin.x), Double(origin.y + height - f.maxY), Double(f.width), Double(f.height)]
        }
        var kids: [[String: Any]] = []
        if depth < 24, seen.insert(ObjectIdentifier(object)).inserted {
            for c in children(of: object) { kids.append(node(c, origin: origin, height: height, depth: depth + 1, seen: &seen)) }
        }
        d["children"] = kids
        return d
    }

    @MainActor static func windowRecord(_ w: NSWindow, main: Bool, kind: String) -> [String: Any] {
        let content = w.contentView ?? NSView()
        let frame = w.convertToScreen(content.convert(content.bounds, to: nil))
        var seen = Set<ObjectIdentifier>()
        let tree = node(content, origin: frame.origin, height: frame.height, depth: 0, seen: &seen)
        var rec: [String: Any] = ["main": main, "kind": kind, "title": w.title, "frame": [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)],
                                  "tree": ["role": "AXWindow", "name": w.title, "enabled": true, "focus": w.isKeyWindow, "bounds": [0.0, 0.0, Double(frame.width), Double(frame.height)], "children": [tree]] as [String: Any]]
        if let responder = w.firstResponder as? NSObject, !(responder is NSWindow) { rec["firstResponder"] = String(describing: type(of: responder)) }
        return rec
    }

    /// `main`: the host window. Every other window, sheet and child window of the process is listed after it, deepest-presented last.
    @MainActor static func dump(main: NSWindow, scale: Double) -> [String: Any] {
        var windows: [[String: Any]] = [windowRecord(main, main: true, kind: "window")]
        var seenWindows: Set<ObjectIdentifier> = [ObjectIdentifier(main)]
        func visit(_ w: NSWindow) {
            for s in w.sheets where seenWindows.insert(ObjectIdentifier(s)).inserted { windows.append(windowRecord(s, main: false, kind: "sheet")); visit(s) }
            for c in w.childWindows ?? [] where seenWindows.insert(ObjectIdentifier(c)).inserted { windows.append(windowRecord(c, main: false, kind: "panel")); visit(c) }
        }
        visit(main)
        for w in NSApp.windows where seenWindows.insert(ObjectIdentifier(w)).inserted {
            // windows the process created for presentation (NSAlert, panels); never AppKit's own status/tooltip windows
            if w.isVisible || w is NSPanel || w.sheetParent != nil { windows.append(windowRecord(w, main: false, kind: w is NSPanel ? "alert" : "window")) }
        }
        var doc: [String: Any] = ["scale": scale, "windows": windows]
        if let focus = main.firstResponder as? NSObject, !(focus is NSWindow) {
            doc["focusedElement"] = ["name": string(get(focus, "accessibilityLabel")) ?? string(get(focus, "accessibilityTitle")) ?? "", "role": string(get(focus, "accessibilityRole")) ?? "AXGroup"]
        }
        return doc
    }

    @MainActor static func write(main: NSWindow, scale: Double, to path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: dump(main: main, scale: scale), options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }
}
