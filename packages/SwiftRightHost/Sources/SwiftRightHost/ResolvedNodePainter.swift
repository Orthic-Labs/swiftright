import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// What one resolved node paints: ABI primitives and semantics; `structural` nodes only group their children.
public struct NodeEmission {
    public var primitives: [Primitive]
    public var semantic: SemanticNode?
    public var flags: NodeFlags
    public var structural: Bool
}

/// Resolved tree -> ABI paint. One painter per window: it owns the renderer image handles of continuous shapes
/// (replaced as the shape changes, released on removal and at teardown). A host supplies the node's pixel bounds in window
/// coordinates (the runtime's `pixelFrame`, translated if the host places the tree), and brackets each commit:
///
///     painter.beginCommit()
///     ... for each node: painter.emit(node, bounds:) ...
///     try window.commit(transaction)           // success
///     painter.endCommit(committed: true)       // (false when the commit failed: the new handles are released instead)
@MainActor
public final class ResolvedNodePainter {
    public let scale: Float
    let images: ImageRegistering
    let text: TextRunSource?
    private let systemImages: SystemImageRegistry?
    private let log: (String) -> Void
    private var shapeImages: [UInt64: ImageHandle] = [:]
    var pendingShapeImages: [UInt64: ImageHandle] = [:]
    /// The runtime id of the TextField that holds the focus while a commit is painted (`commit(focused:)`); nil when no field is focused.
    var focusedFieldID: String?
    var pendingFieldLayouts: [String: TextFieldLayout] = [:]
    /// Where each TextField of the last committed tree put its text (runtime id), for caret placement and IME candidate anchoring.
    public private(set) var fieldLayouts: [String: TextFieldLayout] = [:]

    public init(images: ImageRegistering, scale: Float, text: TextRunSource? = nil, systemImages: SystemImageRegistry? = nil,
                log: @escaping (String) -> Void = { print($0) }) {
        self.images = images; self.scale = scale; self.text = text; self.systemImages = systemImages; self.log = log
    }

    public func beginCommit() { pendingShapeImages = [:]; pendingFieldLayouts = [:] }

    /// `committed == false` releases the images created for the failed commit and keeps the previous ones.
    public func endCommit(committed: Bool) {
        if committed {
            fieldLayouts = pendingFieldLayouts
            for (id, handle) in shapeImages where pendingShapeImages[id] != handle { _ = images.release(handle) }
            shapeImages = pendingShapeImages
        } else {
            pendingShapeImages.values.forEach { _ = images.release($0) }
        }
        pendingShapeImages = [:]
    }

    public func releaseAll() {
        shapeImages.values.forEach { _ = images.release($0) }
        shapeImages = [:]
        pendingShapeImages.values.forEach { _ = images.release($0) }
        pendingShapeImages = [:]
    }

    /// A solid backdrop node under the whole tree (the window background).
    public struct Background {
        public var id: UInt64, bounds: Rect, color: UInt32
        public init(id: UInt64 = UInt64.max - 1, bounds: Rect, color: UInt32) { self.id = id; self.bounds = bounds; self.color = color }
    }

    /// What a committed tree left behind: the live bridge ids and the runtime id of each.
    public struct Committed {
        public var live: Set<UInt64>
        public var runtimeIDs: [UInt64: String]
        public var nodeCount: Int
    }

    /// The whole path from a resolved tree to one ABI transaction: every node is painted (`emit`), upserted under its parent in order
    /// (the bridge id of a node is its runtime instance + 1), ids no longer present are removed, and `submit` hands the transaction to the
    /// renderer. The painter's image handles follow the outcome of `submit` (kept on success, released on failure). `place` moves each
    /// node's pixel bounds (a host that centres or insets the tree); the optional background is not placed.
    public func commit(root: ResolvedNode, version: UInt64, previousLive: Set<UInt64>, background: Background? = nil,
                       place: (Rect) -> Rect = { $0 }, submit: (SwiftRightBridge.Transaction) throws -> Void) throws -> Committed {
        var nodes: [NodeUpsert] = []
        var current: Set<UInt64> = []
        var runtimeIDs: [UInt64: String] = [:]
        if let background {
            nodes.append(NodeUpsert(id: background.id, bounds: background.bounds, primitives: [.rect(background.bounds, color: background.color)]))
            current.insert(background.id)
        }
        // `focused` is the runtime id of the node a `.focused` modifier gave focus (CommitRecord.focused); the TextField it wraps is the focused field.
        let focusedField = focused.flatMap { Self.focusedField(in: root, modifierID: $0) }
        focusedFieldID = focusedField?.id
        beginCommit()
        var committed = false
        defer { endCommit(committed: committed) }
        func walk(_ n: ResolvedNode, parent: UInt64, order: UInt32, clip: Rect?, textColor: UInt32? = nil) throws {
            let id = UInt64(n.instance + 1)
            current.insert(id)
            runtimeIDs[id] = n.id
            let p = n.pixelFrame
            let bounds = place(Rect(x: Float(p.x), y: Float(p.y), w: Float(p.width), h: Float(p.height)))
            let emission = try emit(n, id: id, bounds: bounds, textColor: textColor)
            // The renderer resets its clip stack per node, so a scrolled-out part of a descendant is clipped by wrapping the node's own
            // primitives in the scroll frame (intersected for nested scroll views).
            var primitives = emission.primitives
            if let clip, !primitives.isEmpty { primitives = [.clipPush(clip)] + primitives + [.clipPop] }
            nodes.append(NodeUpsert(id: id, parent: parent, order: order, flags: emission.flags, bounds: bounds, primitives: primitives, semantic: emission.semantic))
            let childClip = Self.clipsContent(n.kind) ? Self.intersection(clip, bounds) : clip
            // A Button's label takes the button's label colour (grey when the button is disabled) unless the label sets its own.
            let childTextColor = n.kind == "Button" ? ButtonArtwork.labelColor(isEnabled: n.accessibility.isEnabled) << 8 | 0xff : textColor
            for (index, child) in n.children.enumerated() { try walk(child, parent: id, order: UInt32(index), clip: childClip, textColor: childTextColor) }
        }
        try walk(root, parent: background?.id ?? 0, order: 0, clip: nil)
        try submit(SwiftRightBridge.Transaction(version: version, focus: focusedField.map { UInt64($0.instance + 1) } ?? 0, upserts: nodes, removes: Array(previousLive.subtracting(current))))
        committed = true
        return Committed(live: current, runtimeIDs: runtimeIDs, nodeCount: nodes.count)
    }

    /// The first TextField at or under the node with runtime id `modifierID`.
    static func focusedField(in root: ResolvedNode, modifierID: String) -> ResolvedNode? {
        func firstField(_ n: ResolvedNode) -> ResolvedNode? {
            if n.kind == "TextField" { return n }
            for c in n.children { if let f = firstField(c) { return f } }
            return nil
        }
        func find(_ n: ResolvedNode) -> ResolvedNode? {
            if n.id == modifierID { return firstField(n) }
            for c in n.children { if let f = find(c) { return f } }
            return nil
        }
        return find(root)
    }

    /// Containers whose resolved frame clips their descendants (a scroll view shows only its viewport).
    static func clipsContent(_ kind: String) -> Bool { kind == "ScrollView" }

    public static func intersection(_ outer: Rect?, _ inner: Rect) -> Rect {
        guard let outer else { return inner }
        let x0 = max(outer.x, inner.x), y0 = max(outer.y, inner.y)
        let x1 = min(outer.x + outer.w, inner.x + inner.w), y1 = min(outer.y + outer.h, inner.y + inner.h)
        return Rect(x: x0, y: y0, w: max(0, x1 - x0), h: max(0, y1 - y0))
    }

    /// Runtime primitive node kinds (`Graph.kindName`) this paint path does not emit yet; they fail visibly. Every other kind is a
    /// structural container, a modifier or a user-defined composite view, whose children are painted individually.
    static let unpaintedPrimitives: Set<String> = ["TextEditor", "Divider", "Menu", "List"]

    public static func isStructuralContainer(_ kind: String) -> Bool {
        switch kind {
        case "VStack", "HStack", "ZStack", "Overlay", "Layout", "Group", "EmptyView", "Spacer", "ScrollView", "LazyVStack", "LazyHStack": return true
        default: return false
        }
    }

    /// `id` is the bridge node id the caller upserts this node under (image handles are keyed by it).
    /// `textColor` is the colour a Text inherits from an ancestor (a Button's label colour), 0xRRGGBBAA; a Text's own foreground wins.
    public func emit(_ node: ResolvedNode, id: UInt64, bounds: Rect, textColor: UInt32? = nil) throws -> NodeEmission {
        switch node.kind {
        case "Text":
            guard let string = node.text, !string.isEmpty else { return NodeEmission(primitives: [], semantic: nil, flags: [], structural: false) }
            guard node.opacity == 1 else { throw HostPaintError.unsupportedTextPaintStyle }
            guard let text else { throw HostPaintError.unsupportedNode("Text (no text measurer)") }
            let color = try node.style.foreground.map { try HostPaint.rgba($0, opacity: 1, scheme: node.style.colorScheme) } ?? textColor ?? (node.style.colorScheme == .dark ? try HostPaint.rgba(.semantic("label"), opacity: 1, scheme: .dark) : nil)
            let run = try color.map { try text.run(text: string, font: node.style.font, bounds: bounds, color: $0) }
                ?? text.run(text: string, font: node.style.font, bounds: bounds)
            return NodeEmission(primitives: [.text(run, x: bounds.x, y: bounds.y)],
                                semantic: SemanticNode(role: .staticText, label: string, identifier: node.id, disabled: !node.accessibility.isEnabled),
                                flags: [], structural: false)

        case "Rectangle", "RoundedRectangle", "Circle":
            switch try ShapePainter.plan(node, bounds: bounds, scale: scale) {
            case .primitive(let primitive):
                return NodeEmission(primitives: [primitive], semantic: nil, flags: [], structural: false)
            case .continuous(let request):
                let result = try ContinuousShapeRaster.primitive(images, request)
                if let stale = pendingShapeImages[id] { _ = images.release(stale) }
                pendingShapeImages[id] = result.image
                return NodeEmission(primitives: [result.primitive], semantic: nil, flags: [], structural: false)
            }

        case "Toggle":
            let plan = try TogglePainter.plan(node, bounds: bounds, scale: scale)
            let handle = try images.registerImage(width: UInt32(plan.image.width), height: UInt32(plan.image.height), rgba: plan.image.rgba, stride: 0)
            if let stale = pendingShapeImages[id] { _ = images.release(stale) }
            pendingShapeImages[id] = handle
            return NodeEmission(primitives: [.image(handle, plan.placement)],
                                semantic: SemanticNode(role: plan.role, label: node.accessibility.label ?? "", value: node.accessibility.value ?? "",
                                                       actions: plan.isEnabled ? [.invoke] : [], identifier: node.id, toggled: plan.toggled,
                                                       disabled: !plan.isEnabled),
                                flags: [.hitTarget], structural: false)

        case "Button":
            let plan = try ButtonPainter.plan(node, bounds: bounds, scale: scale)
            let handle = try images.registerImage(width: UInt32(plan.image.width), height: UInt32(plan.image.height), rgba: plan.image.rgba, stride: 0)
            if let stale = pendingShapeImages[id] { _ = images.release(stale) }
            pendingShapeImages[id] = handle
            return NodeEmission(primitives: [.image(handle, plan.placement)],
                                semantic: SemanticNode(role: .button, label: node.accessibility.label ?? "",
                                                       actions: plan.isEnabled ? [.invoke] : [], identifier: node.id, disabled: !plan.isEnabled),
                                flags: [.hitTarget], structural: false)

        case "TextField":
            return try emitTextField(node, id: id, bounds: bounds)

        case "Color":
            guard let color = node.color else { throw HostPaintError.colorMetadataRequired }
            return NodeEmission(primitives: [.rect(bounds, color: try HostPaint.rgba(color, opacity: node.opacity, scheme: node.style.colorScheme))], semantic: nil, flags: [], structural: false)

        case "Image":
            guard let systemImages else { throw HostPaintError.unsupportedNode("Image (no system image registry)") }
            return NodeEmission(primitives: [try systemImagePrimitive(node, bounds: bounds, registry: systemImages)],
                                semantic: SemanticNode(role: .image, label: node.accessibility.label ?? node.image?.name ?? "", identifier: node.id,
                                                       disabled: !node.accessibility.isEnabled),
                                flags: [], structural: false)

        default:
            // A composite (user-defined) view paints through its children; only runtime primitives the paint path has no emission for fail.
            guard !Self.unpaintedPrimitives.contains(node.kind) else { throw HostPaintError.unsupportedNode(node.kind) }
            return NodeEmission(primitives: [], semantic: nil, flags: [], structural: true)
        }
    }

    private func systemImagePrimitive(_ node: ResolvedNode, bounds: Rect, registry: SystemImageRegistry) throws -> Primitive {
        guard let reference = node.image else { throw HostPaintError.systemImageContractMismatch("no image reference") }
        guard registry.supports(reference) else { throw HostPaintError.systemImageContractMismatch("symbol '\(reference.name)' is not in the table") }
        guard let sizing = node.imageSizing, sizing.isResizable, sizing.scalesToFit, sizing.resizingMode == .stretch else {
            throw HostPaintError.systemImageContractMismatch("only resizable().scaledToFit() symbols are painted")
        }
        guard bounds.w > 0, bounds.h > 0 else { throw HostPaintError.systemImageContractMismatch("empty frame") }
        let tint = try HostPaint.rgba(node.style.foreground ?? .semantic(registry.defaultForeground(for: reference)), opacity: node.opacity, scheme: node.style.colorScheme)
        let targetWidth = UInt32(max(1, bounds.w)), targetHeight = UInt32(max(1, bounds.h))
        let handle = try registry.handle(for: reference, tint: tint, width: targetWidth, height: targetHeight)
        let inset = registry.canvasInset(for: reference)
        log("SYSTEM_IMAGE_FRAME name=\(reference.name) xPX=\(Int(bounds.x)) yPX=\(Int(bounds.y)) widthPX=\(Int(bounds.w)) heightPX=\(Int(bounds.h)) canvasInsetPX=\(Int(inset)) tintRGBA=\(String(format: "%08x", tint))")
        return .image(handle, Rect(x: bounds.x - inset + imageGuardBand, y: bounds.y - inset + imageGuardBand,
                                   w: bounds.w + 2 * inset - 2 * imageGuardBand, h: bounds.h + 2 * inset - 2 * imageGuardBand))
    }
}
