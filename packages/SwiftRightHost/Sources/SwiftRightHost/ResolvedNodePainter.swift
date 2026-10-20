import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// What one resolved node paints: ABI primitives and semantics; `structural` nodes only group their children.
public struct NodeEmission {
    public var primitives: [Primitive]
    public var semantic: SemanticNode?
    public var flags: NodeFlags
    public var structural: Bool
    /// The bounds the node is upserted under (hit-testing and the accessibility rectangle) when they are not the node's frame: a Slider's is its control, not its labels.
    public var bounds: Rect? = nil
    /// The node's own painting is clipped to this rectangle (a Text whose run is wider than the frame it was given: the Mac clips to the frame, decision L1).
    public var clipTo: Rect? = nil
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
    /// Points to pixels for what is being painted: the display scale, times the factor of any `.scaleEffect` above the node being emitted (SR2 R4).
    public private(set) var scale: Float
    /// The display scale the painter was made with.
    public let baseScale: Float
    /// Text nodes painted under a `.scaleEffect` since this painter was made: text keeps its size (runs are measured at the display scale) and is centred on its scaled place.
    public private(set) var scaleTextLimitationCount = 0
    /// `.brightness` amounts above the node being emitted, outermost first (SR2 R4): applied to its colours innermost first, each clamped.
    private var brightness: [Float] = []
    /// Image content (not shapes) painted under `.brightness` since this painter was made: bitmaps are drawn unadjusted.
    public private(set) var brightnessImageLimitationCount = 0

    /// The `.scaleEffect` factor on the Text being emitted (R4b, #42); 1 when unscaled.
    private var textScaleFactor: Float = 1

    /// `font` at `factor` x its point size (a text style takes its macOS size and weight), in half points within the measurer's 9...40 pt table; nil when it has no size.
    static func scaledFont(_ font: Font?, by factor: Float) -> Font? {
        let base = font ?? .body
        let m = base.metadata
        var size: Float? = m?.pointSize.map(Float.init)
        var weight = m?.weight ?? .regular
        if size == nil, let style = m?.textStyle ?? (font == nil || base.id == "textStyle.body" ? "body" : nil), let entry = MacTextStyles.all[style] {
            size = entry.size
            weight = m?.weight ?? (m?.isEmphasized == true ? entry.emphasized : entry.weight)
        }
        guard let pt = size, m?.isCustom != true else { return nil }
        let scaled = min(max((pt * factor * 2).rounded(.down) / 2, 9), 40)
        var out = m?.design.map { Font.system(size: CGFloat(scaled), weight: weight, design: $0) } ?? Font.system(size: CGFloat(scaled), weight: weight)
        if m?.monospacedDigit == true { out = out.monospacedDigit() }
        return out
    }

    /// `.clipShape` masks above the node being emitted (SR2 R6). Host-rasterised shapes and solid rects are masked; text and bitmaps are clipped to the clip's
    /// bounding rect only (the renderer's clip stack is rectangular).
    private var clipMasks: [ClipMask] = []
    /// Text and bitmap nodes painted under a non-rectangular `.clipShape` since this painter was made (rect-clipped only).
    public private(set) var clipShapeLimitationCount = 0

    private func registerRGBA(_ image: ContinuousRGBAImage) throws -> ImageHandle {
        try images.registerImage(width: UInt32(image.width), height: UInt32(image.height), rgba: image.rgba, stride: 0)
    }

    /// `result` with every active clip mask multiplied into its alpha.
    private func masked(_ image: ContinuousRGBAImage, placement: Rect) -> ContinuousRGBAImage {
        guard !clipMasks.isEmpty else { return image }
        return ClipMask.apply(clipMasks, to: image, originX: Int((placement.x - imageGuardBand).rounded()), originY: Int((placement.y - imageGuardBand).rounded()))
    }

    /// A colour (0xRRGGBBAA) through the `.brightness` amounts above the node being emitted.
    func adjusted(_ rgba: UInt32) -> UInt32 {
        guard !brightness.isEmpty else { return rgba }
        func channel(_ shift: UInt32) -> UInt32 {
            var v = Float((rgba >> shift) & 255) / 255
            for b in brightness.reversed() { v = min(max(v + b, 0), 1) }
            return UInt32((v * 255).rounded()) << shift
        }
        return channel(24) | channel(16) | channel(8) | (rgba & 255)
    }
    let images: ImageRegistering
    let text: TextRunSource?
    private let systemImages: SystemImageRegistry?
    private let log: (String) -> Void
    private var shapeImages: [UInt64: ImageHandle] = [:]
    var pendingShapeImages: [UInt64: ImageHandle] = [:]
    /// Registered pixel images (`Image(decorative:scale:)`), one per content id, painted size and opacity: kept while a committed tree uses them.
    /// `level` is the `Image.Interpolation` (-1 = never set, 0 none ... 3 high).
    struct PixelKey: Hashable { var contentID: UInt64; var width: UInt32; var height: UInt32; var alpha: UInt8; var level: Int8 = -1 }
    /// The last variant registered for each image node (bridge node id): what the transient path keeps painting while the size is changing.
    private var lastPixelKey: [UInt64: PixelKey] = [:]
    /// Live resize and animation (wave 1 block I2, docs/foundations-images-fonts.md 1.3): while true, an image node whose destination size changed keeps painting its last registered variant
    /// (the renderer scales it on the GPU) instead of building a new device-exact buffer every frame; it is a documented transient difference. The host sets it false when the size has been
    /// stable (the end of a window drag, the end of an animation) and commits once more: every image then rebuilds at its exact size. Settled captures never run with it true.
    public var isLiveResizing = false
    private var pixelImages: [PixelKey: ImageHandle] = [:]
    private var pendingPixelImages: [PixelKey: ImageHandle] = [:]
    /// The runtime id of the TextField that holds the focus while a commit is painted (`commit(focused:)`); nil when no field is focused.
    var focusedFieldID: String?
    /// True while the keyboard is in a List (the host sets it on a pointer press in the list or a navigation key): a selection then paints in the accent colour,
    /// otherwise grey, as AppKit draws a table that is not the first responder.
    public var listIsActive = false
    var pendingFieldLayouts: [String: TextFieldLayout] = [:]
    /// Where each TextField of the last committed tree put its text (runtime id), for caret placement and IME candidate anchoring.
    public private(set) var fieldLayouts: [String: TextFieldLayout] = [:]
    /// The legacy scroller of each List and ScrollView in the last committed tree, by runtime id (window pixels; see `scrollerRect(for:)`).
    public private(set) var scrollerLayouts: [String: ScrollerLayout] = [:]
    /// Painted non-shape nodes found under a `.rotationEffect` since this painter was made. The host rotates shapes only (the ABI transform is translation only), so such content is painted
    /// unrotated and counted here, with one log line per node kind (reported limitation, #35); it is never faked.
    public private(set) var rotationLimitationCount = 0
    private var rotationLimitationKinds: Set<String> = []
    /// Bridge id bit of a scroller node: a List or ScrollView's scroller is a child node of its own, `id | scrollerNodeFlag`.
    static let scrollerNodeFlag: UInt64 = 1 << 62
    /// Whether the renderer takes a `.scrollBar` node (`Bridge.supportsScrollBar`, rev 0.11). When true, a scroller publishes a scroll bar
    /// semantic with its range (value 0...1); when false it stays a plain painted node, since an older renderer refuses the role.
    public let publishesScrollBars: Bool

    public init(images: ImageRegistering, scale: Float, text: TextRunSource? = nil, systemImages: SystemImageRegistry? = nil,
                publishesScrollBars: Bool = false, log: @escaping (String) -> Void = { print($0) }) {
        self.images = images; self.scale = scale; self.baseScale = scale; self.text = text; self.systemImages = systemImages; self.log = log
        self.publishesScrollBars = publishesScrollBars
    }

    /// The scroll bar semantic of a scroller: role `.scrollBar` (vertical in the renderer), the range the thumb's position on 0...1, with the
    /// arrow step (one wheel line) and the page (the viewport less the page overlap) as fractions of the offset travel, so UIA's SmallChange and
    /// LargeChange match the keyboard and the wheel. `lineHeight` is one wheel line: a List's row height, a ScrollView's 10 pt (issue #31).
    /// Nil when the renderer does not publish scroll bars.
    func scrollBarSemantic(for scroll: ScrollState, lineHeight: CGFloat = ScrollerMetrics.pointsPerLine) -> SemanticNode? {
        guard publishesScrollBars else { return nil }
        let maxOffset = scroll.maxOffset
        let step = maxOffset > 0 ? Double(lineHeight) / maxOffset : 0
        let page = Double(max(0, CGFloat(scroll.viewportHeight) - ScrollerMetrics.pageOverlap))
        let jump = maxOffset > 0 ? page / maxOffset : 0
        return SemanticNode(role: .scrollBar, label: "", range: SliderRange(value: scroll.value, min: 0, max: 1, step: step, jump: jump))
    }

    public func beginCommit() { pendingShapeImages = [:]; pendingPixelImages = [:]; pendingFieldLayouts = [:] }

    /// `committed == false` releases the images created for the failed commit and keeps the previous ones.
    public func endCommit(committed: Bool) {
        if committed {
            fieldLayouts = pendingFieldLayouts
            for (id, handle) in shapeImages where pendingShapeImages[id] != handle { _ = images.release(handle) }
            shapeImages = pendingShapeImages
            for (key, handle) in pixelImages where pendingPixelImages[key] != handle { _ = images.release(handle) }
            pixelImages = pendingPixelImages
            lastPixelKey = lastPixelKey.filter { pixelImages[$0.value] != nil }
        } else {
            pendingShapeImages.values.forEach { _ = images.release($0) }
            for (key, handle) in pendingPixelImages where pixelImages[key] != handle { _ = images.release(handle) }
        }
        pendingShapeImages = [:]
        pendingPixelImages = [:]
    }

    public func releaseAll() {
        shapeImages.values.forEach { _ = images.release($0) }
        shapeImages = [:]
        pendingShapeImages.values.forEach { _ = images.release($0) }
        pendingShapeImages = [:]
        var pixelHandles = Set(pixelImages.values)
        pixelHandles.formUnion(pendingPixelImages.values)
        pixelHandles.forEach { _ = images.release($0) }
        pixelImages = [:]
        pendingPixelImages = [:]
        lastPixelKey = [:]
    }

    /// The strip of a List or ScrollView's legacy vertical scroller in the last committed tree, in window pixels (the space of the node bounds the
    /// commit upserts); nil when the node shows none (not a List or ScrollView, or its content does not overflow). For hit-testing by the case host.
    public func scrollerRect(for node: ResolvedNode) -> CGRect? {
        scrollerLayouts[node.id].map { ScrollerPainter.cgRect($0.strip) }
    }

    /// The thumb of the scroller `scrollerRect(for:)` describes, in window pixels; nil when there is none.
    public func thumbRect(for node: ResolvedNode) -> CGRect? {
        scrollerLayouts[node.id].map { ScrollerPainter.cgRect($0.thumb) }
    }

    /// A solid backdrop node under the whole tree (the window background).
    public struct Background {
        public var id: UInt64, bounds: Rect, color: UInt32
        public init(id: UInt64 = UInt64.max - 1, bounds: Rect, color: UInt32) { self.id = id; self.bounds = bounds; self.color = color }
    }

    /// The accessibility modifiers above a node, as the host applies them to the element beneath (round 5 block 32). An outer modifier wins over an inner one.
    /// `label` and `value` replace the element's; `traits` change its role (`isImage`, `isButton`) or state (`isSelected`); `isHeader`, `isLink`, `isSearchField`
    /// and the rest have no role in the renderer ABI and are carried, not exposed. `hint` has no field in the ABI either (SWR_SEMANTIC has label, value, role,
    /// actions, flags, identifier, toggled): it is recorded on the resolved tree and not published.
    struct A11yPatch: Equatable {
        var label: String?
        var value: String?
        var traits: Set<String> = []
        var isEmpty: Bool { label == nil && value == nil && traits.isEmpty }
        /// This patch (outer) over `inner`.
        func overriding(_ inner: A11yPatch) -> A11yPatch {
            A11yPatch(label: label ?? inner.label, value: value ?? inner.value, traits: traits.union(inner.traits))
        }
    }

    /// Applies a patch to the semantic an element emitted (nil: the node publishes none).
    static func apply(_ patch: A11yPatch, to semantic: SemanticNode?, bounds: Rect) -> SemanticNode? {
        guard !patch.isEmpty else { return semantic }
        guard var s = semantic else {
            // a view with no element of its own (a Rectangle) becomes an image element when it is given the trait and a label
            if patch.traits.contains("isImage"), let label = patch.label { return SemanticNode(role: .image, label: label, value: patch.value ?? "") }
            return nil
        }
        if let label = patch.label { s.label = label }
        if let value = patch.value { s.value = value }
        if patch.traits.contains("isImage"), s.role == .staticText || s.role == .group { s.role = .image }
        if patch.traits.contains("isButton"), s.role == .staticText || s.role == .group || s.role == .image { s.role = .button; s.actions.insert(.invoke) }
        if patch.traits.contains("isSelected") { s.selected = true }
        return s
    }

    /// The texts of the Text nodes under a node, in order, joined by ", " (macOS: `.accessibilityElement(children: .combine)` over two Texts reads "Memory, 1.2 GB").
    static func combinedLabel(_ n: ResolvedNode) -> String {
        var parts: [String] = []
        func collect(_ item: ResolvedNode) {
            if item.kind == "Text", let t = item.text, !t.isEmpty { parts.append(t) }
            else if item.accessibility.role == "button", let l = item.accessibility.label, !l.isEmpty { parts.append(l) }
            else { item.children.forEach(collect) }
        }
        n.children.forEach(collect)
        return parts.joined(separator: ", ")
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
                       place: (Rect) -> Rect = { $0 }, focused: String? = nil, submit: (SwiftRightBridge.Transaction) throws -> Void) throws -> Committed {
        var nodes: [NodeUpsert] = []
        var current: Set<UInt64> = []
        var runtimeIDs: [UInt64: String] = [:]
        var scrollers: [String: ScrollerLayout] = [:]
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
        func walk(_ n: ResolvedNode, parent: UInt64, order: UInt32, clip: Rect?, rotations: [ShapeRotation] = [], textColor: UInt32? = nil, row: ListPainter.Row? = nil, rowList: (bounds: Rect, look: ListLook)? = nil, inButton: Bool = false, a11y: A11yPatch = A11yPatch(), hidden: Bool = false, transform: PaintScale = .identity, brightness: [Float] = [], clipMasks: [ClipMask] = []) throws {
            let id = UInt64(n.instance + 1)
            current.insert(id)
            runtimeIDs[id] = n.id
            let p = n.pixelFrame
            let laidOut = place(Rect(x: Float(p.x), y: Float(p.y), w: Float(p.width), h: Float(p.height)))
            // `.scaleEffect` above (SR2 R4): bounds are mapped through the accumulated scale and the node is painted at display scale x the factor, so
            // radii, stroke widths and rasters scale with it. Text keeps its measured size, centred on its scaled place (a counted limitation).
            let scaledText = !transform.isIdentity && n.kind == "Text"
            let bounds = transform.isIdentity ? laidOut : transform.map(laidOut)
            textScaleFactor = scaledText ? transform.uniform : 1
            let nodeScale = scaledText ? baseScale : baseScale * transform.uniform
            scale = nodeScale
            self.brightness = brightness
            self.clipMasks = clipMasks
            defer { scale = baseScale; self.brightness = []; self.clipMasks = []; textScaleFactor = 1 }
            // A factor of 0 (`.scaleEffect(shown ? 1 : 0)`, the first frame of a pop-in) paints nothing: no raster may be asked for at scale 0.
            let collapsed = !transform.isIdentity && (transform.sx == 0 || transform.sy == 0)
            var emission: NodeEmission
            if collapsed { emission = NodeEmission(primitives: [], semantic: nil, flags: [], structural: false) }
            else if let row, let rowList { emission = try emitListRow(n, id: id, row: row, look: rowList.look, contentBounds: bounds, textColor: textColor) }
            else { emission = try emit(n, id: id, bounds: bounds, textColor: textColor, rotations: rotations) }
            let childTransform = n.scaleEffect.map { transform.scaled(by: $0, about: laidOut) } ?? transform
            let childBrightness = n.brightness.map { brightness + [Float($0)] } ?? brightness
            var childMasks = clipMasks
            if let clip = n.clipShape, clip.geometry != .rectangle {
                childMasks.append(try ClipMask.render(geometry: clip.geometry, fillStyle: clip.fillStyle, bounds: bounds, scale: nodeScale))
            }
            // `.rotationEffect` (anchor in this node's pixel frame, which is its child's frame) rotates every shape leaf beneath it.
            let childRotations = n.rotation.map { rotations + [ShapeRotation($0, bounds: bounds)] } ?? rotations
            // A Button's label is the button's accessible name: its Text publishes no node of its own (as on macOS).
            if inButton, n.kind == "Text" { emission.semantic = nil }
            // Accessibility modifiers (round 5 block 32): the patch above this node applies to the first element beneath it; hidden removes a whole subtree; an
            // `.accessibilityElement(children: .combine | .ignore)` node is one element and its descendants publish none.
            var childA11y = a11y
            var childHidden = hidden
            var childInButton = inButton
            if n.kind.hasPrefix("modifier.accessibility") {
                let acc = n.accessibility
                var own = A11yPatch()
                if n.kind == "modifier.accessibilityLabel" { own.label = acc.label }
                if n.kind == "modifier.accessibilityValue" { own.value = acc.value }
                if n.kind == "modifier.accessibilityTraits", !acc.addedTraits.isEmpty { own.traits = Set(acc.addedTraits) }
                childA11y = a11y.overriding(own)
                if n.kind == "modifier.accessibilityHidden", acc.isHidden { childHidden = true }
                if n.kind == "modifier.accessibilityElement", !hidden, let behavior = acc.childBehavior, behavior == "combine" || behavior == "ignore" {
                    let label = behavior == "combine" ? Self.combinedLabel(n) : (a11y.label ?? "")
                    emission.semantic = Self.apply(a11y, to: SemanticNode(role: behavior == "combine" ? .staticText : .group, label: a11y.label ?? label, identifier: n.id), bounds: bounds)
                    emission.semantic?.label = behavior == "combine" ? (a11y.label ?? label) : label
                    childHidden = true
                    childA11y = A11yPatch()
                }
            } else if !a11y.isEmpty {
                if emission.semantic != nil || a11y.traits.contains("isImage") {
                    emission.semantic = Self.apply(a11y, to: emission.semantic, bounds: bounds)
                    childA11y = A11yPatch()
                } else if n.children.count != 1 {
                    childA11y = A11yPatch()   // a container with several children has no single element to take the patch
                }
            }
            if hidden { emission.semantic = nil }
            // A List row is hit anywhere along its width, not only where its content is.
            let nodeBounds = row?.rect ?? emission.bounds ?? bounds
            // The renderer resets its clip stack per node, so a scrolled-out part of a descendant is clipped by wrapping the node's own
            // primitives in the scroll frame (intersected for nested scroll views).
            var primitives = emission.primitives
            let paintClip: Rect? = emission.clipTo.map { Self.intersection(clip, $0) } ?? clip
            if let paintClip, !primitives.isEmpty { primitives = [.clipPush(paintClip)] + primitives + [.clipPop] }
            nodes.append(NodeUpsert(id: id, parent: parent, order: order, flags: emission.flags, bounds: nodeBounds, primitives: primitives, semantic: emission.semantic))
            let childClip = Self.clipsContent(n.kind) || n.clipShape != nil ? Self.intersection(clip, bounds) : clip
            // A Button's label takes the button's label colour (grey when the button is disabled) unless the label sets its own.
            let childTextColor = n.kind == "Button" ? try ButtonPainter.labelColor(of: n) : textColor
            if n.kind == "List" {
                let look = ListPainter.look(of: n)
                let rows = ListPainter.rows(of: n, bounds: bounds, scale: scale)
                for (index, child) in n.children.enumerated() where index < rows.count {
                    // Text inside an active selection is white.
                    let colour = rows[index].isSelected && ListPainter.selectionColor(active: listIsActive, isEnabled: rows[index].isEnabled) == ListPainter.selectionActive ? ListPainter.selectedTextColor : childTextColor
                    try walk(child, parent: id, order: UInt32(index), clip: childClip, rotations: childRotations, textColor: colour, row: rows[index], rowList: (bounds, look), a11y: childA11y, hidden: childHidden, transform: childTransform, brightness: childBrightness, clipMasks: childMasks)
                }
            } else {
                for (index, child) in n.children.enumerated() { try walk(child, parent: id, order: UInt32(index), clip: childClip, rotations: childRotations, textColor: childTextColor, inButton: childInButton || n.kind == "Button" || n.kind == "modifier.onTapGesture", a11y: childA11y, hidden: childHidden, transform: childTransform, brightness: childBrightness, clipMasks: childMasks) }
            }
            // The children's walks reset the painter to the display scale: this node's own scale and brightness apply again to what it paints after them.
            scale = nodeScale
            self.brightness = brightness
            self.clipMasks = clipMasks
            // The legacy scroller of a List or ScrollView is painted above its content: a child node ordered after the last child, clipped to the container.
            if n.kind == "List" || n.kind == "ScrollView", let scroll = n.scroll, let layout = ScrollerPainter.layout(frame: bounds, scale: scale, scroll: scroll) {
                let scrollerID = id | Self.scrollerNodeFlag
                current.insert(scrollerID)
                runtimeIDs[scrollerID] = n.id
                scrollers[n.id] = layout
                let scrollerClip = Self.intersection(clip, bounds)
                var scrollerPrimitives: [Primitive] = [.clipPush(scrollerClip)]
                scrollerPrimitives += ScrollerPainter.primitives(for: layout, scale: scale)
                scrollerPrimitives.append(.clipPop)
                // One wheel line is one row of a List (the runtime's `scrollWheel` line), 10 pt for a ScrollView.
                let line = n.kind == "List" ? n.children.map { ListMetrics.rowHeight(forContent: CGFloat($0.frame.height)) }.min() ?? ScrollerMetrics.pointsPerLine : ScrollerMetrics.pointsPerLine
                nodes.append(NodeUpsert(id: scrollerID, parent: id, order: UInt32(n.children.count), bounds: layout.strip, primitives: scrollerPrimitives,
                                        semantic: scrollBarSemantic(for: scroll, lineHeight: line)))
            }
        }
        try walk(root, parent: background?.id ?? 0, order: 0, clip: nil)
        try submit(SwiftRightBridge.Transaction(version: version, focus: focusedField.map { UInt64($0.instance + 1) } ?? 0, upserts: nodes, removes: Array(previousLive.subtracting(current))))
        committed = true
        scrollerLayouts = scrollers
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
    static func clipsContent(_ kind: String) -> Bool { kind == "ScrollView" || kind == "List" || kind == "modifier.clipped" }

    public static func intersection(_ outer: Rect?, _ inner: Rect) -> Rect {
        guard let outer else { return inner }
        let x0 = max(outer.x, inner.x), y0 = max(outer.y, inner.y)
        let x1 = min(outer.x + outer.w, inner.x + inner.w), y1 = min(outer.y + outer.h, inner.y + inner.h)
        return Rect(x: x0, y: y0, w: max(0, x1 - x0), h: max(0, y1 - y0))
    }

    /// Runtime primitive node kinds (`Graph.kindName`) this paint path does not emit yet; they fail visibly. Every other kind is a
    /// structural container, a modifier or a user-defined composite view, whose children are painted individually.
    static let unpaintedPrimitives: Set<String> = ["TextEditor", "Menu"]

    public static func isStructuralContainer(_ kind: String) -> Bool {
        switch kind {
        case "VStack", "HStack", "ZStack", "Overlay", "Background", "Layout", "Group", "EmptyView", "Spacer", "ScrollView", "LazyVStack", "LazyHStack": return true
        default: return false
        }
    }

    /// `id` is the bridge node id the caller upserts this node under (image handles are keyed by it).
    /// `textColor` is the colour a Text inherits from an ancestor (a Button's label colour), 0xRRGGBBAA; a Text's own foreground wins.
    /// `rotations` are the `.rotationEffect`s above the node, outermost first, anchors in window pixels: shapes are rotated through their path raster; any other painted content stays unrotated and is reported.
    public func emit(_ node: ResolvedNode, id: UInt64, bounds: Rect, textColor: UInt32? = nil, rotations: [ShapeRotation] = []) throws -> NodeEmission {
        var emission = try emitContent(node, id: id, bounds: bounds, textColor: textColor, rotations: rotations)
        if !brightness.isEmpty {
            emission.primitives = emission.primitives.map {
                if case .rect(let r, let color, let radius, let borderColor, let borderWidth) = $0 {
                    return .rect(r, color: adjusted(color), radius: radius, borderColor: adjusted(borderColor), borderWidth: borderWidth)
                }
                return $0
            }
            if !Self.isShapeKind(node.kind), emission.primitives.contains(where: { if case .image = $0 { return true } else { return false } }) { brightnessImageLimitationCount += 1 }
        }
        if !clipMasks.isEmpty {
            var out: [Primitive] = []
            for (index, primitive) in emission.primitives.enumerated() {
                guard case .rect(let r, let color, let radius, let borderColor, let borderWidth) = primitive, !clipMasks.allSatisfy({ $0.covers(r) }) else {
                    if case .text = primitive { clipShapeLimitationCount += 1 }
                    if case .image = primitive, !Self.isShapeKind(node.kind) { clipShapeLimitationCount += 1 }
                    out.append(primitive)
                    continue
                }
                // A solid rect across the clip's edge: drawn by the path raster and masked (its border, inside the rect as the renderer draws it, as a centred stroke inset by half).
                let corner = RoundedCornerStyle.circular
                let rounded = ShapeGeometry.roundedRectangle(cornerRadius: CGFloat(radius / scale), style: corner)
                var images: [(ContinuousRGBAImage, Rect)] = []
                if color & 255 != 0, let fill = try PathShapeRaster.render(PathShapeRequest(bounds: r, scale: scale, geometry: rounded, fillRGBA: color, strokeRGBA: nil)) {
                    images.append((fill.image, fill.placement))
                }
                if borderWidth > 0, borderColor & 255 != 0,
                   let ring = try PathShapeRaster.render(PathShapeRequest(bounds: r, scale: scale, geometry: .inset(rounded, by: CGFloat(borderWidth / scale / 2)), fillRGBA: nil, strokeRGBA: borderColor,
                                                                          strokeStyle: StrokeStyle(lineWidth: CGFloat(borderWidth / scale)))) {
                    images.append((ring.image, ring.placement))
                }
                for (k, (image, placement)) in images.enumerated() {
                    let maskedImage = masked(image, placement: placement)
                    let handle = try registerRGBA(maskedImage)
                    let key = id | (UInt64(0x200 + index * 2 + k) << 48)
                    if let stale = pendingShapeImages[key] { _ = self.images.release(stale) }
                    pendingShapeImages[key] = handle
                    out.append(.image(handle, placement))
                }
            }
            emission.primitives = out
        }
        // `.allowsHitTesting(false)` (R1, #36): the node takes no pointer hits. Its painting and its accessibility actions are unchanged.
        if !node.accessibility.allowsHitTesting, emission.flags.contains(.hitTarget) { emission.flags.remove(.hitTarget) }
        if ShapeRotation.isRotated(rotations), !emission.primitives.isEmpty, !Self.isShapeKind(node.kind) {
            rotationLimitationCount += 1
            if rotationLimitationKinds.insert(node.kind).inserted {
                log("rotationEffect limitation: \(node.kind) is painted unrotated (the host rotates shapes only; the renderer transform is translation only)")
            }
        }
        return emission
    }

    static func isShapeKind(_ kind: String) -> Bool { kind == "Rectangle" || kind == "RoundedRectangle" || kind == "Circle" || kind == "Capsule" || kind == "Path" }

    private func emitContent(_ node: ResolvedNode, id: UInt64, bounds: Rect, textColor: UInt32?, rotations: [ShapeRotation]) throws -> NodeEmission {
        switch node.kind {
        case "Text":
            guard let string = node.text, !string.isEmpty else { return NodeEmission(primitives: [], semantic: nil, flags: [], structural: false) }
            guard let text else { throw HostPaintError.unsupportedNode("Text (no text measurer)") }
            // Opacity is baked into the text run's colour alpha (the run is created per presented opacity, so an animated fade re-measures each frame).
            // A text without its own colour fades the primary label colour.
            let inherited = textColor.map { ($0 & 0xffffff00) | UInt32((Double($0 & 255) * node.opacity).rounded()) }
            var color = try node.style.foreground.map { try HostPaint.rgba($0, opacity: node.opacity, scheme: node.style.colorScheme) } ?? inherited
                ?? (node.style.colorScheme == .dark || node.opacity != 1 || !brightness.isEmpty ? try HostPaint.rgba(.semantic("label"), opacity: node.opacity, scheme: node.style.colorScheme) : nil)
            color = color.map(adjusted)
            // R4b (#42): a one-line Text under `.scaleEffect` is shaped at the scaled point size and placed at its scaled origin. Otherwise (wrapped text, a font with
            // no size, a size outside the measurer's table) it keeps its measured size, centred on its scaled place (counted).
            if textScaleFactor != 1 {
                let unscaled = Rect(x: bounds.x + bounds.w / 2 - bounds.w / textScaleFactor / 2, y: bounds.y + bounds.h / 2 - bounds.h / textScaleFactor / 2,
                                    w: bounds.w / textScaleFactor, h: bounds.h / textScaleFactor)
                let shade = try color ?? HostPaint.rgba(.semantic("label"), opacity: node.opacity, scheme: node.style.colorScheme)
                if !string.contains("\n"), let scaledFont = Self.scaledFont(node.style.font, by: textScaleFactor), let measurer = text as? TextMeasurer {
                    _ = measurer.measure(TextMeasureRequest(text: string, fontID: scaledFont.id, proposedWidth: nil, scale: CGFloat(baseScale), fontMetadata: scaledFont.metadata))
                    if let natural = try text.naturalRun(text: string, font: scaledFont, color: shade),
                       let one = try text.naturalRun(text: string, font: node.style.font, color: shade).map({ $0.height }) ?? Optional(natural.height / textScaleFactor),
                       unscaled.h < one * 1.5 {
                        return NodeEmission(primitives: [.text(natural.run, x: bounds.x, y: bounds.y)],
                                            semantic: SemanticNode(role: .staticText, label: string, identifier: node.id, disabled: !node.accessibility.isEnabled),
                                            flags: [], structural: false)
                    }
                }
                scaleTextLimitationCount += 1
                let run = try color.map { try text.run(text: string, font: node.style.font, bounds: unscaled, color: $0) } ?? text.run(text: string, font: node.style.font, bounds: unscaled)
                return NodeEmission(primitives: [.text(run, x: unscaled.x, y: unscaled.y)],
                                    semantic: SemanticNode(role: .staticText, label: string, identifier: node.id, disabled: !node.accessibility.isEnabled),
                                    flags: [], structural: false)
            }
            let run = try color.map { try text.run(text: string, font: node.style.font, bounds: bounds, color: $0) }
                ?? text.run(text: string, font: node.style.font, bounds: bounds)
            var emission = NodeEmission(primitives: [.text(run, x: bounds.x, y: bounds.y)],
                                semantic: SemanticNode(role: .staticText, label: string, identifier: node.id, disabled: !node.accessibility.isEnabled),
                                flags: [], structural: false)
            if text.runOverflows(text: string, font: node.style.font, bounds: bounds) { emission.clipTo = bounds }
            return emission

        case "Rectangle", "RoundedRectangle", "Circle", "Capsule", "Path":
            switch try ShapePainter.plan(node, bounds: bounds, scale: scale, rotations: rotations) {
            case .primitive(let primitive):
                return NodeEmission(primitives: [primitive], semantic: nil, flags: [], structural: false)
            case .path(var request):
                request.fillRGBA = request.fillRGBA.map(adjusted); request.strokeRGBA = request.strokeRGBA.map(adjusted)
                // A vector path (trimmed, inset, dashed, custom, or a style the ABI rect cannot draw): rasterised on the host and registered as one image, kept under the
                // node id like the continuous route, so the commit releases the previous frame's handle when the node repaints or goes away. Nothing to draw -> no primitive.
                guard let result = try PathShapeRaster.render(request) else { return NodeEmission(primitives: [], semantic: nil, flags: [], structural: false) }
                let image = masked(result.image, placement: result.placement)
                let handle = try images.registerImage(width: UInt32(image.width), height: UInt32(image.height), rgba: image.rgba, stride: 0)
                if let stale = pendingShapeImages[id] { _ = images.release(stale) }
                pendingShapeImages[id] = handle
                return NodeEmission(primitives: [.image(handle, result.placement)], semantic: nil, flags: [], structural: false)
            case .continuous(var request):
                request.fillRGBA = request.fillRGBA.map(adjusted); request.strokeRGBA = request.strokeRGBA.map(adjusted)
                // One image, or horizontal bands of one when the shape is over the rasteriser's work limit (round 5 block 30). Band k's handle is kept under a key
                // derived from the node id so a commit releases every band of a node that went away or changed.
                // A shape with no area (a zero-width bar, a frame under half a device pixel) draws nothing, as in SwiftUI (hub gap R8).
                guard request.bounds.w > 0, request.bounds.h > 0 else { return NodeEmission(primitives: [], semantic: nil, flags: [], structural: false) }
                var primitives: [Primitive] = []
                let rendered: [ContinuousShapeRaster.Result]
                do { rendered = try ContinuousShapeRaster.renderBands(request) }
                catch HostPaintError.continuousShapeRasterInput(2) { return NodeEmission(primitives: [], semantic: nil, flags: [], structural: false) }
                for (band, result) in rendered.enumerated() {
                    let image = masked(result.image, placement: result.placement)
                    let handle = try images.registerImage(width: UInt32(image.width), height: UInt32(image.height), rgba: image.rgba, stride: 0)
                    let key = band == 0 ? id : id | (UInt64(band) << 48)
                    if let stale = pendingShapeImages[key] { _ = images.release(stale) }
                    pendingShapeImages[key] = handle
                    primitives.append(.image(handle, result.placement))
                }
                return NodeEmission(primitives: primitives, semantic: nil, flags: [], structural: false)
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

        case "SliderControl":
            let plan = try SliderPainter.plan(node, bounds: bounds, scale: scale)
            let handle = try images.registerImage(width: UInt32(plan.image.width), height: UInt32(plan.image.height), rgba: plan.image.rgba, stride: 0)
            if let stale = pendingShapeImages[id] { _ = images.release(stale) }
            pendingShapeImages[id] = handle
            // role slider with the UIA RangeValue (ABI 0.9): value, minimum, maximum, SmallChange (the arrow-key step), LargeChange
            let range = SliderRange(value: plan.value, min: plan.lower, max: plan.upper, step: plan.smallChange, jump: plan.largeChange)
            return NodeEmission(primitives: [.image(handle, plan.placement)],
                                semantic: SemanticNode(role: .slider, label: node.accessibility.label ?? "", value: node.accessibility.value ?? "",
                                                       actions: plan.isEnabled ? [.focus] : [], identifier: node.id, disabled: !plan.isEnabled, range: range),
                                flags: plan.isEnabled ? [.hitTarget, .focusable] : [.hitTarget], structural: false, bounds: plan.controlBounds)

        case "modifier.onTapGesture":
            // a view with a tap gesture is ONE pressable accessibility node (decision H8): a button named by the text it holds, invoked by the accessibility action; its text publishes none
            return NodeEmission(primitives: [],
                                semantic: SemanticNode(role: .button, label: node.accessibility.label ?? Self.combinedLabel(node), actions: node.accessibility.isEnabled ? [.invoke] : [],
                                                       identifier: node.id, disabled: !node.accessibility.isEnabled),
                                flags: [.hitTarget], structural: false)

        case "Button":
            let plan = try ButtonPainter.plan(node, bounds: bounds, scale: scale)
            var primitives: [Primitive] = []
            if let image = plan.image {
                let handle = try images.registerImage(width: UInt32(image.width), height: UInt32(image.height), rgba: image.rgba, stride: 0)
                if let stale = pendingShapeImages[id] { _ = images.release(stale) }
                pendingShapeImages[id] = handle
                primitives = [.image(handle, plan.placement)]
            }
            return NodeEmission(primitives: primitives,
                                semantic: SemanticNode(role: .button, label: node.accessibility.label ?? "",
                                                       actions: plan.isEnabled ? [.invoke] : [], identifier: node.id, disabled: !plan.isEnabled),
                                flags: [.hitTarget], structural: false)

        case "TextField":
            return try emitTextField(node, id: id, bounds: bounds)

        case "List":
            return NodeEmission(primitives: try ListPainter.primitives(for: node, bounds: bounds, scale: scale),
                                semantic: SemanticNode(role: .list, label: node.accessibility.label ?? "", identifier: node.id, disabled: !node.accessibility.isEnabled),
                                flags: [], structural: false)

        case "Divider":
            // Measured on macOS 27 (light): the separator is black at alpha 25/255 (230 over white, (0,123,230) over (0,136,255)), as thick as the layout box (1 pt, snapped to the
            // device grid like any edge: 2 or 3 px at scale 2.5). Dark appearance (round 5 block 31): white at alpha 25/255 (`HostPaint.darkSemantic`).
            return NodeEmission(primitives: [.rect(bounds, color: try HostPaint.rgba(.semantic("separator"), opacity: node.opacity, scheme: node.style.colorScheme))], semantic: nil, flags: [], structural: false)

        case "Color":
            guard let color = node.color else { throw HostPaintError.colorMetadataRequired }
            return NodeEmission(primitives: [.rect(bounds, color: try HostPaint.rgba(color, opacity: node.opacity, scheme: node.style.colorScheme))], semantic: nil, flags: [], structural: false)

        case "Image":
            if case .pixels(let image, _)? = node.image {
                return NodeEmission(primitives: [try pixelImagePrimitive(node, image, bounds: bounds, id: id)],
                                    semantic: SemanticNode(role: .image, label: node.accessibility.label ?? "", identifier: node.id,
                                                           disabled: !node.accessibility.isEnabled),
                                    flags: [], structural: false)
            }
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

    /// One row of a List: its selection highlight (a rect primitive), and the row's semantics (a list item, selected or not) over the row's whole width.
    func emitListRow(_ node: ResolvedNode, id: UInt64, row: ListPainter.Row, look: ListLook, contentBounds: Rect, textColor: UInt32?) throws -> NodeEmission {
        var primitives: [Primitive] = []
        switch ListPainter.highlight(for: row, look: look, scale: scale, active: listIsActive) {
        case .flat(let rect, let rgba)?:
            primitives = [.rect(rect, color: rgba)]
        case .rounded(let rect, let rgb)?:
            let w = Int(rect.w.rounded()), h = Int(rect.h.rounded())
            let image = ListHighlightArtwork.render(widthPX: w, heightPX: h, scale: scale, rgb: rgb)
            let handle = try images.registerImage(width: UInt32(image.width), height: UInt32(image.height), rgba: image.rgba, stride: 0)
            if let stale = pendingShapeImages[id] { _ = images.release(stale) }
            pendingShapeImages[id] = handle
            primitives = [.image(handle, Rect(x: rect.x + imageGuardBand, y: rect.y + imageGuardBand, w: Float(w) - 2 * imageGuardBand, h: Float(h) - 2 * imageGuardBand))]
        case nil:
            break
        }
        // a row that is itself a primitive (a bare Text) still paints its own content over the highlight
        if !Self.isStructuralKind(node.kind) { primitives += try emit(node, id: id, bounds: contentBounds, textColor: textColor).primitives }
        return NodeEmission(primitives: primitives,
                            semantic: SemanticNode(role: .listItem, label: node.accessibility.label ?? "", identifier: node.id, selected: row.isSelected, disabled: !row.isEnabled),
                            flags: [.hitTarget], structural: false)
    }

    static func isStructuralKind(_ kind: String) -> Bool { !(kind == "Text" || kind == "Color" || kind == "Image" || kind == "Rectangle" || kind == "RoundedRectangle" || kind == "Circle" || kind == "Capsule" || kind == "Path") }

    private func systemImagePrimitive(_ node: ResolvedNode, bounds: Rect, registry: SystemImageRegistry) throws -> Primitive {
        guard let reference = node.image else { throw HostPaintError.systemImageContractMismatch("no image reference") }
        guard registry.supports(reference) else { throw HostPaintError.systemImageContractMismatch("symbol '\(reference.name)' is not in the table") }
        // Two measured uses: resizable().scaledToFit(), and a non-resizable symbol at the environment font (sized by the font, never stretched).
        var fontSize: Double?
        var weight = "regular"
        if let sizing = node.imageSizing {
            guard sizing.isResizable, sizing.scalesToFit, sizing.resizingMode == .stretch else {
                throw HostPaintError.systemImageContractMismatch("only resizable().scaledToFit() or font-sized symbols are painted")
            }
            guard registry.supportsResizable(reference) else {
                throw HostPaintError.systemImageContractMismatch("symbol '\(reference.name)' has no measured resizable layout")
            }
        } else {
            guard registry.supportsFontSized(reference) else {
                throw HostPaintError.systemImageContractMismatch("symbol '\(reference.name)' has no measured font-sized layout")
            }
            guard let spec = SystemImageRegistry.fontSpec(node.style.font),
                  registry.supportsFontSized(reference, weight: spec.weight) else {
                throw HostPaintError.systemImageContractMismatch("symbol font '\(node.style.font?.id ?? "none")' is not measured (system fonts and text styles in the regular, semibold and bold weights only)")
            }
            fontSize = spec.size; weight = spec.weight
        }
        guard bounds.w > 0, bounds.h > 0 else { throw HostPaintError.systemImageContractMismatch("empty frame") }
        let tint = try HostPaint.rgba(node.style.foreground ?? .semantic(registry.defaultForeground(for: reference)), opacity: node.opacity, scheme: node.style.colorScheme)
        let targetWidth = fontSize == nil ? UInt32(max(1, bounds.w)) : UInt32(max(1, bounds.w.rounded())), targetHeight = fontSize == nil ? UInt32(max(1, bounds.h)) : UInt32(max(1, bounds.h.rounded()))
        let handle = try registry.handle(for: reference, tint: tint, width: targetWidth, height: targetHeight, fontSize: fontSize, weight: weight)
        let inset = registry.canvasInset(for: reference, fontSize: fontSize, weight: weight, width: targetWidth, height: targetHeight)
        log("SYSTEM_IMAGE_FRAME name=\(reference.name) xPX=\(Int(bounds.x)) yPX=\(Int(bounds.y)) widthPX=\(Int(bounds.w)) heightPX=\(Int(bounds.h)) canvasInsetPX=\(Int(inset)) tintRGBA=\(String(format: "%08x", tint))")
        return .image(handle, Rect(x: bounds.x - inset + imageGuardBand, y: bounds.y - inset + imageGuardBand,
                                   w: bounds.w + 2 * inset - 2 * imageGuardBand, h: bounds.h + 2 * inset - 2 * imageGuardBand))
    }

    /// Decoded pixels painted to fill the node rect, as a device-pixel-exact buffer (wave 1 block I2): the image is resampled to the node's snapped device-pixel size with the filter fitted to the Mac
    /// for its `Image.Interpolation` level (`ImageResampler`) and registered 1:1, so the renderer's own sampling never decides a pixel. An image drawn at its own size is registered as is.
    /// Node opacity scales the alpha. Tiled and cap-inset images are refused. A destination over the renderer's limits (8192 px a side, 64 MiB) registers the source and lets the renderer scale it.
    private func pixelImagePrimitive(_ node: ResolvedNode, _ image: RGBAImage, bounds: Rect, id: UInt64 = 0) throws -> Primitive {
        if let sizing = node.imageSizing {
            guard sizing.resizingMode == .stretch, sizing.capInsets == EdgeInsets() else {
                throw HostPaintError.systemImageContractMismatch("pixel images paint stretched only (no tiling, no cap insets)")
            }
        }
        guard bounds.w >= 1, bounds.h >= 1 else { throw HostPaintError.systemImageContractMismatch("empty frame") }
        guard node.opacity >= 0, node.opacity <= 1 else { throw HostPaintError.invalidFillOpacity }
        let targetW = Int(bounds.w.rounded()), targetH = Int(bounds.h.rounded())
        let level = node.imageSizing?.interpolation
        let levelCode: Int8 = level.map { l -> Int8 in switch l { case .none: return 0; case .low: return 1; case .medium: return 2; case .high: return 3 } } ?? -1
        let oversize = targetW > 8192 || targetH > 8192 || targetW * targetH * 4 > 64 << 20
        let w = oversize ? UInt32(min(image.width, max(1, targetW))) : UInt32(targetW), h = oversize ? UInt32(min(image.height, max(1, targetH))) : UInt32(targetH)
        var key = PixelKey(contentID: image.contentID, width: w, height: h, alpha: UInt8((node.opacity * 255).rounded()), level: levelCode)
        var transient = false
        if isLiveResizing, id != 0, let last = lastPixelKey[id], last != key, last.contentID == key.contentID, last.level == key.level, last.alpha == key.alpha,
           pendingPixelImages[last] != nil || pixelImages[last] != nil {
            key = last; transient = true      // keep the last registered variant: the renderer scales it into the new rect
        }
        let handle: ImageHandle
        if let known = pendingPixelImages[key] ?? pixelImages[key] {
            handle = known
        } else {
            var source = image
            if oversize {
                if Int(w) != image.width || Int(h) != image.height { source = ImageDecoder.resample(image, width: Int(w), height: Int(h)) }
            } else {
                source = ImageResampler.resample(image, width: Int(w), height: Int(h), level: level)
            }
            var rgba = source.rgba
            if key.alpha != 255 {
                for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = UInt8((Int(rgba[i]) * Int(key.alpha) + 127) / 255) }
            }
            handle = try images.registerImage(width: UInt32(source.width), height: UInt32(source.height), rgba: rgba, stride: 0)
        }
        pendingPixelImages[key] = handle
        if id != 0 { lastPixelKey[id] = key }
        log("PIXEL_IMAGE id=\(String(image.contentID, radix: 16)) source=\(image.width)x\(image.height) registered=\(key.width)x\(key.height) xPX=\(Int(bounds.x)) yPX=\(Int(bounds.y)) widthPX=\(Int(bounds.w)) heightPX=\(Int(bounds.h)) alpha=\(key.alpha) level=\(levelCode) transient=\(transient)\(oversize ? " oversize" : "")")
        return .image(handle, Rect(x: bounds.x + imageGuardBand, y: bounds.y + imageGuardBand, w: bounds.w - 2 * imageGuardBand, h: bounds.h - 2 * imageGuardBand))
    }
}
