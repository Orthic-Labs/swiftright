import Foundation

// Cross-platform normalizer for the F1 comparison. Same shape as TraceKit's MacAXNormalizer / UIANormalizer
// (role maps, named stripped containers, identifier-based ids) with the extensions each recorded in RESULT.md
// as adaptations A1..An. Anything not named here keeps its raw role so that it shows up as a diff.

struct RNode {
    var role: String
    var subrole: String?
    var id: String?
    var title: String?
    var label: String?        // Mac AXDescription / Windows Name
    var value: String?
    var settable = false      // Mac: AXValue settable
    var actions: [String] = []   // Mac AX action names / Windows pattern names
    var hasFocus = false
    var children: [RNode] = []
}

struct NormOptions {
    var keepLists = false     // strict mode: keep list / list-item containers (A7 off)
}

struct Normalized {
    var nodes: [TNode]
    var focusedId: String?
    var applied: Set<String>   // adaptation ids that actually fired
}

private func ne(_ s: String?) -> String? {
    guard let s, !s.isEmpty else { return nil }
    return s
}

enum Cross {
    // Named Mac platform containers (CONTRACT §5) plus AXToolbar (A2).
    static let macStripped: Set<String> = ["AXCell", "AXColumn", "AXScrollArea", "AXHostingView", "AXGroup", "AXToolbar"]
    static let macChromeSubroles: Set<String> = ["AXCloseButton", "AXFullScreenButton", "AXMinimizeButton"]
    static let macRoleMap: [String: String] = [
        "AXOutline": "list", "AXButton": "button", "AXTextField": "text-field", "AXStaticText": "static-text", "AXWindow": "window",
    ]
    static let winStripped: Set<String> = ["Pane", "Group", "Custom"]
    static let winDropped: Set<String> = ["TitleBar"]
    static let winRoleMap: [String: String] = [
        "Edit": "text-field", "Button": "button", "List": "list", "ListItem": "list-item", "Window": "window", "Text": "static-text",
    ]

    static func macRole(_ n: RNode) -> String {
        if n.role == "AXRow" && n.subrole == "AXOutlineRow" { return "list-item" }
        return macRoleMap[n.role] ?? n.role
    }

    static func normalizeMac(_ app: RNode, _ opt: NormOptions) -> Normalized {
        // Application root: take its window (A1: AXApplication is a platform root, menu bar excluded at capture).
        let window = app.children.first { $0.role == "AXWindow" } ?? app
        var ctx = Ctx(opt: opt, platform: .mac)
        ctx.applied.insert("A1")
        ctx.visitRoot(window)
        return ctx.result()
    }

    static func normalizeWin(_ root: RNode, _ opt: NormOptions) -> Normalized {
        var ctx = Ctx(opt: opt, platform: .win)
        ctx.visitRoot(root)
        return ctx.result()
    }

    enum Platform { case mac, win }

    struct Ctx {
        var opt: NormOptions
        var platform: Platform
        var out: [TNode] = []
        var focused: String?
        var applied: Set<String> = []
        var lastFieldPrefix: String?   // for A5

        init(opt: NormOptions, platform: Platform) { self.opt = opt; self.platform = platform }

        func result() -> Normalized { Normalized(nodes: out, focusedId: focused, applied: applied) }

        func role(_ n: RNode) -> String {
            platform == .mac ? Cross.macRole(n) : (Cross.winRoleMap[n.role] ?? n.role)
        }

        func isStripped(_ n: RNode, canonicalRole r: String) -> Bool {
            switch platform {
            case .mac:
                if Cross.macStripped.contains(n.role) { return true }
            case .win:
                if Cross.winStripped.contains(n.role) { return true }
            }
            if !opt.keepLists && (r == "list" || r == "list-item") { return true }
            return false
        }

        mutating func visitRoot(_ window: RNode) {
            let rid = "window"
            // A3: window id fixed to `window`; the title is host-chosen chrome and is not compared.
            out.append(TNode(id: rid, role: "window", label: nil, value: nil, actions: [], parent: nil, order: 0))
            if window.hasFocus { focused = rid }
            var order = 0
            visitChildren(of: window, parentId: rid, order: &order, isWindow: true)
        }

        mutating func visitChildren(of n: RNode, parentId: String, order: inout Int, isWindow: Bool) {
            var kids = n.children
            if platform == .mac && isWindow {
                // A2: Mac places the toolbar after the content as a window-level sibling; Windows puts the button in the
                // content first. Canonical order visits the toolbar subtree first.
                let tb = kids.filter { $0.role == "AXToolbar" }
                if !tb.isEmpty { applied.insert("A2") }
                kids = tb + kids.filter { $0.role != "AXToolbar" }
            }
            for c in kids { visit(c, parentId: parentId, order: &order, windowChild: isWindow) }
        }

        mutating func visit(_ n: RNode, parentId: String, order: inout Int, windowChild: Bool) {
            // Dropped subtrees (named window chrome).
            if platform == .mac {
                if let s = n.subrole, Cross.macChromeSubroles.contains(s) { applied.insert("A4"); return }
                if windowChild && n.role == "AXStaticText" { applied.insert("A4"); return }   // window title text
                if n.role == "AXMenuBar" { applied.insert("A4"); return }
            } else if Cross.winDropped.contains(n.role) {
                applied.insert("A4"); return
            }
            let r = role(n)
            if isStripped(n, canonicalRole: r) {
                if r == "list" || r == "list-item" { applied.insert("A7") }
                for c in n.children { visit(c, parentId: parentId, order: &order, windowChild: false) }
                return
            }
            let my = order
            order += 1

            var id: String
            if let ident = ne(n.id) {
                id = ident
                if r == "text-field" { lastFieldPrefix = ident.hasSuffix("/field") ? String(ident.dropLast("/field".count)) : ident }
            } else if r == "static-text", let p = lastFieldPrefix {
                // A5: the unidentified "local N" counter text takes the id `<row prefix>/local` from the text field that
                // precedes it in document order (same rule on both platforms).
                id = "\(p)/local"
                lastFieldPrefix = nil
                applied.insert("A5")
            } else {
                id = "anon:\(parentId)#\(my)"
            }

            var label: String?
            var value: String?
            switch r {
            case "static-text":
                // A6: static text content is the canonical label (Mac AXValue, Windows Name).
                label = ne(platform == .mac ? (n.value ?? n.title ?? n.label) : (n.label ?? n.value))
            case "button":
                label = ne(n.label ?? n.title)
            case "text-field":
                label = ne(n.title ?? n.label)
                value = n.value
            default:
                label = ne(n.title ?? n.label)
                value = n.value
            }

            // A8: canonical actions are the two the contract uses for SR0 controls. Everything else is a named drop.
            var actions = Set<String>()
            switch platform {
            case .mac:
                if n.actions.contains("AXPress") && r == "button" { actions.insert("activate") }
                if n.settable { actions.insert("set-value") }
            case .win:
                if n.actions.contains("InvokePattern") { actions.insert("activate") }
                if n.actions.contains("ValuePattern") { actions.insert("set-value") }
            }

            out.append(TNode(id: id, role: r, label: label, value: value, actions: actions.sorted(),
                             parent: parentId, order: my))
            if n.hasFocus { focused = id }
            var childOrder = 0
            for c in n.children { visit(c, parentId: id, order: &childOrder, windowChild: false) }
        }
    }
}
