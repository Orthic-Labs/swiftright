import Foundation

private func nonEmpty(_ s: String?) -> String? {
    guard let s, !s.isEmpty else { return nil }
    return s
}

/// Raw macOS AX node as written by the AXRecorder dump (`probes/sr0-o/ax-routes/out/ax-tree.json`).
/// The recorder stores AXDescription under `label`; `frame` and other keys are ignored.
public struct RawAXNode: Codable, Sendable, Equatable {
    public var role: String?
    public var subrole: String?
    public var identifier: String?
    public var label: String?
    public var title: String?
    public var value: String?
    public var actions: [String]?
    public var children: [RawAXNode]?

    public init(role: String?, subrole: String? = nil, identifier: String? = nil, label: String? = nil,
                title: String? = nil, value: String? = nil, actions: [String]? = nil, children: [RawAXNode]? = nil) {
        self.role = role; self.subrole = subrole; self.identifier = identifier; self.label = label
        self.title = title; self.value = value; self.actions = actions; self.children = children
    }
}

/// Maps raw macOS AX output to canonical nodes per CONTRACT §5.
/// Only the named platform containers are stripped; unknown roles pass through under their raw name
/// so that an unlisted container shows up as a diff instead of disappearing.
public enum MacAXNormalizer {
    public static let strippedRoles: Set<String> = ["AXCell", "AXColumn", "AXScrollArea", "AXHostingView", "AXGroup"]

    public static let roleMap: [String: String] = [
        "AXOutline": "list",
        "AXButton": "button",
        "AXTextField": "text-field",
        "AXStaticText": "static-text",
        "AXWindow": "window",
    ]

    public static let actionMap: [String: String] = [
        "AXPress": "activate",
        "AXConfirm": "confirm",
        "AXShowMenu": "show-menu",
        "AXRaise": "raise",
    ]

    /// Stable id rule: AXIdentifier when it is unique in the tree (AppKit menus reuse identifiers such as
    /// `_recentItemRequested:`); otherwise `identifier~<parentId>#<order>`; no identifier gives `anon:<parentId>#<order>`.
    public static func normalize(_ root: RawAXNode) -> [CanonicalNode] {
        var identifierCounts: [String: Int] = [:]
        countIdentifiers(root, into: &identifierCounts)
        let duplicated = Set(identifierCounts.filter { $0.value > 1 }.keys)
        var out: [CanonicalNode] = []
        var rootOrder = 0
        visit(root, parentId: nil, order: &rootOrder, duplicated: duplicated, out: &out)
        return out
    }

    private static func countIdentifiers(_ n: RawAXNode, into counts: inout [String: Int]) {
        if let id = nonEmpty(n.identifier) { counts[id, default: 0] += 1 }
        for child in n.children ?? [] { countIdentifiers(child, into: &counts) }
    }

    private static func visit(_ n: RawAXNode, parentId: String?, order: inout Int, duplicated: Set<String>, out: inout [CanonicalNode]) {
        let rawRole = n.role ?? "AXUnknown"
        if strippedRoles.contains(rawRole) {
            // Flatten: children take this node's sibling slots under the nearest kept ancestor.
            for child in n.children ?? [] {
                visit(child, parentId: parentId, order: &order, duplicated: duplicated, out: &out)
            }
            return
        }
        let myOrder = order
        order += 1
        let id: String
        if let ident = nonEmpty(n.identifier) {
            id = duplicated.contains(ident) ? "\(ident)~\(parentId ?? "root")#\(myOrder)" : ident
        } else {
            id = "anon:\(parentId ?? "root")#\(myOrder)"
        }
        let label = rawRole == "AXButton" ? nonEmpty(n.label) : (nonEmpty(n.title) ?? nonEmpty(n.label))
        out.append(CanonicalNode(
            id: id,
            role: canonicalRole(rawRole, subrole: n.subrole),
            label: label,
            value: n.value,
            actions: canonicalActions(n.actions ?? []),
            parent: parentId,
            order: myOrder
        ))
        var childOrder = 0
        for child in n.children ?? [] {
            visit(child, parentId: id, order: &childOrder, duplicated: duplicated, out: &out)
        }
    }

    static func canonicalRole(_ raw: String, subrole: String?) -> String {
        if raw == "AXRow" && subrole == "AXOutlineRow" { return "list-item" }
        return roleMap[raw] ?? raw
    }

    static func canonicalActions(_ raw: [String]) -> [String] {
        Array(Set(raw.map { actionMap[$0] ?? $0 })).sorted()
    }
}

/// Raw Windows UI Automation node (stub shape; a live UIA dump is not yet recorded for SR0-O).
public struct RawUIANode: Codable, Sendable, Equatable {
    public var controlType: String?
    public var name: String?
    public var automationId: String?
    public var value: String?
    public var patterns: [String]?
    public var children: [RawUIANode]?

    public init(controlType: String?, name: String? = nil, automationId: String? = nil, value: String? = nil,
                patterns: [String]? = nil, children: [RawUIANode]? = nil) {
        self.controlType = controlType; self.name = name; self.automationId = automationId
        self.value = value; self.patterns = patterns; self.children = children
    }
}

/// Stub UIA normalizer. Same contract as the Mac normalizer: named containers only are stripped.
public enum UIANormalizer {
    public static let strippedTypes: Set<String> = ["Pane", "Group", "Custom"]

    public static let roleMap: [String: String] = [
        "Edit": "text-field",
        "Button": "button",
        "List": "list",
        "ListItem": "list-item",
        "Window": "window",
        "Text": "static-text",
    ]

    public static let patternMap: [String: String] = [
        "InvokePattern": "activate",
        "ValuePattern": "set-value",
        "ExpandCollapsePattern": "expand-collapse",
    ]

    public static func normalize(_ root: RawUIANode) -> [CanonicalNode] {
        var counts: [String: Int] = [:]
        countIds(root, into: &counts)
        let duplicated = Set(counts.filter { $0.value > 1 }.keys)
        var out: [CanonicalNode] = []
        var rootOrder = 0
        visit(root, parentId: nil, order: &rootOrder, duplicated: duplicated, out: &out)
        return out
    }

    private static func countIds(_ n: RawUIANode, into counts: inout [String: Int]) {
        if let id = nonEmpty(n.automationId) { counts[id, default: 0] += 1 }
        for child in n.children ?? [] { countIds(child, into: &counts) }
    }

    private static func visit(_ n: RawUIANode, parentId: String?, order: inout Int, duplicated: Set<String>, out: inout [CanonicalNode]) {
        let type = n.controlType ?? "Unknown"
        if strippedTypes.contains(type) {
            for child in n.children ?? [] {
                visit(child, parentId: parentId, order: &order, duplicated: duplicated, out: &out)
            }
            return
        }
        let myOrder = order
        order += 1
        let id: String
        if let ident = nonEmpty(n.automationId) {
            id = duplicated.contains(ident) ? "\(ident)~\(parentId ?? "root")#\(myOrder)" : ident
        } else {
            id = "anon:\(parentId ?? "root")#\(myOrder)"
        }
        out.append(CanonicalNode(
            id: id,
            role: roleMap[type] ?? type,
            label: nonEmpty(n.name),
            value: n.value,
            actions: Array(Set((n.patterns ?? []).map { patternMap[$0] ?? $0 })).sorted(),
            parent: parentId,
            order: myOrder
        ))
        var childOrder = 0
        for child in n.children ?? [] {
            visit(child, parentId: id, order: &childOrder, duplicated: duplicated, out: &out)
        }
    }
}
