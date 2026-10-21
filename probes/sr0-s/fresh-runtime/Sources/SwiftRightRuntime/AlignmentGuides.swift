import Foundation

// Issue #68 (MarkdownUI on SwiftRight): custom alignments and `.alignmentGuide`.
//
// SwiftUI model: every view has, for each alignment, a guide value (a position along an axis in its own coordinate space). A guide is `explicit` when `.alignmentGuide`
// (or a container that aligns on it) set it, else implicit (the alignment's default: bounds for the standard ones, `AlignmentID.defaultValue(in:)` for a custom one).
// A stack aligns its children by making their guide values coincide.
//
// What is implemented: HStack, VStack, ZStack (`alignment:`), and `.overlay` / `.background` (`alignment:`) honour custom alignments and `.alignmentGuide` on the
// standard ones. Grid cells honour `.alignmentGuide` on the horizontal and vertical standard alignments. Not honoured: custom alignments in `.frame(alignment:)` (centred),
// explicit guides of children are merged by "first child wins" in a stack that does not align on that guide (SwiftUI's merge rule for unaligned stacks is approximated).

/// Apple: https://developer.apple.com/documentation/swiftui/alignmentid
public protocol AlignmentID {
    /// The guide value of a view that has no explicit value for this alignment.
    static func defaultValue(in context: ViewDimensions) -> CGFloat
}

/// Identity of a custom alignment: its `AlignmentID` type.
struct AlignmentKey: Hashable, @unchecked Sendable {
    let id: ObjectIdentifier
    let type: any AlignmentID.Type

    init(_ type: any AlignmentID.Type) {
        id = ObjectIdentifier(type)
        self.type = type
    }

    static func == (lhs: AlignmentKey, rhs: AlignmentKey) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func defaultValue(in context: ViewDimensions) -> CGFloat { type.defaultValue(in: context) }
}

/// One alignment on one axis: the key of a guide.
enum GuideKey: Hashable, Sendable {
    case h(HorizontalAlignment)
    case v(VerticalAlignment)
}

/// The size of a view and its alignment guides, as `.alignmentGuide` and `AlignmentID.defaultValue(in:)` see it.
/// Apple: https://developer.apple.com/documentation/swiftui/viewdimensions
public struct ViewDimensions: Equatable {
    /// Apple: https://developer.apple.com/documentation/swiftui/viewdimensions/width
    public let width: CGFloat
    /// Apple: https://developer.apple.com/documentation/swiftui/viewdimensions/height
    public let height: CGFloat
    let firstBaseline: CGFloat
    let lastBaseline: CGFloat
    let explicit: [GuideKey: CGFloat]

    init(width: CGFloat, height: CGFloat, firstBaseline: CGFloat? = nil, lastBaseline: CGFloat? = nil, explicit: [GuideKey: CGFloat] = [:]) {
        self.width = width
        self.height = height
        self.firstBaseline = firstBaseline ?? height
        self.lastBaseline = lastBaseline ?? height
        self.explicit = explicit
    }

    /// The value of a horizontal guide: the explicit one, else the alignment's default (a custom alignment's `defaultValue(in:)`).
    /// Apple: https://developer.apple.com/documentation/swiftui/viewdimensions/subscript(_:)-6vqd7
    public subscript(guide: HorizontalAlignment) -> CGFloat {
        if let value = explicit[.h(guide)] { return value }
        switch guide.kind {
        case .leading: return 0
        case .center: return width / 2
        case .trailing: return width
        case .custom(let key): return key.defaultValue(in: self)
        }
    }

    /// The value of a vertical guide: the explicit one, else the alignment's default. A view with no text has its bottom edge as both baselines.
    /// Apple: https://developer.apple.com/documentation/swiftui/viewdimensions/subscript(_:)-9sux0
    public subscript(guide: VerticalAlignment) -> CGFloat {
        if let value = explicit[.v(guide)] { return value }
        switch guide.kind {
        case .top: return 0
        case .center: return height / 2
        case .bottom: return height
        case .firstTextBaseline: return firstBaseline
        case .lastTextBaseline: return lastBaseline
        case .custom(let key): return key.defaultValue(in: self)
        }
    }

    /// The explicit value of a horizontal guide, nil when none was set.
    /// Apple: https://developer.apple.com/documentation/swiftui/viewdimensions/subscript(explicit:)-2fbqv
    public subscript(explicit guide: HorizontalAlignment) -> CGFloat? { explicit[.h(guide)] }

    /// The explicit value of a vertical guide, nil when none was set.
    /// Apple: https://developer.apple.com/documentation/swiftui/viewdimensions/subscript(explicit:)-1ryv2
    public subscript(explicit guide: VerticalAlignment) -> CGFloat? { explicit[.v(guide)] }

    subscript(key: GuideKey) -> CGFloat {
        switch key {
        case .h(let alignment): return self[alignment]
        case .v(let alignment): return self[alignment]
        }
    }
}

/// An `.alignmentGuide` modifier: sets the explicit value of `key` for the wrapped view.
struct AlignmentGuideSpec {
    let key: GuideKey
    let compute: (ViewDimensions) -> CGFloat
}

extension View {
    /// Sets the view's explicit horizontal guide for `alignment` to `computeValue(dimensions of the view)`. The view's size and place in its own container are unchanged;
    /// a stack that aligns on `alignment` moves the view so that its guide coincides with its siblings'.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/alignmentguide(_:computevalue:)-6y3u2
    public func alignmentGuide(_ g: HorizontalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        Modified(content: self, spec: .alignmentGuide(AlignmentGuideSpec(key: .h(g), compute: computeValue)))
    }

    /// Sets the view's explicit vertical guide for `alignment` to `computeValue(dimensions of the view)`.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/alignmentguide(_:computevalue:)-1v1q2
    public func alignmentGuide(_ g: VerticalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        Modified(content: self, spec: .alignmentGuide(AlignmentGuideSpec(key: .v(g), compute: computeValue)))
    }
}

// MARK: - Engine

@MainActor
extension Graph {
    /// True when `node` or a descendant carries an `.alignmentGuide` for `key`.
    func subtreeHasGuide(_ node: Node, _ key: GuideKey) -> Bool {
        if case .modifier(.alignmentGuide(let spec)) = node.kind, spec.key == key { return true }
        for child in node.childNodes where subtreeHasGuide(child, key) { return true }
        return false
    }

    /// The alignment a stack aligns its children on (its cross axis); nil for the overlap and overlay axes.
    func stackGuideKey(_ spec: StackSpec) -> GuideKey? {
        if let custom = spec.customGuide { return custom }
        switch spec.axis {
        case .horizontal:
            switch spec.cross {
            case .start: return .v(.top)
            case .middle: return .v(.center)
            case .end: return .v(.bottom)
            case .firstBaseline: return .v(.firstTextBaseline)
            case .lastBaseline: return .v(.lastTextBaseline)
            }
        case .vertical:
            switch spec.cross {
            case .start: return .h(.leading)
            case .middle, .firstBaseline, .lastBaseline: return .h(.center)
            case .end: return .h(.trailing)
            }
        case .overlap, .overlay:
            return nil
        }
    }

    /// The guide a horizontal or vertical stack aligns its children on, when guide alignment applies: the stack uses a custom alignment, or a child subtree sets an
    /// explicit guide for the stack's own alignment. Otherwise nil: the legacy placement (which is identical for the standard alignments) applies.
    func guidedKey(_ children: [Node], _ spec: StackSpec) -> GuideKey? {
        guard spec.axis == .horizontal || spec.axis == .vertical, !children.isEmpty, let key = stackGuideKey(spec) else { return nil }
        if spec.customGuide != nil { return key }
        guard alignmentGuidesLive else { return nil }
        return children.contains { subtreeHasGuide($0, key) } ? key : nil
    }

    /// Whether the overlap / overlay axes align by guides.
    func overlapGuided(_ children: [Node], _ spec: StackSpec) -> Bool {
        let h = spec.alignment.horizontal, v = spec.alignment.vertical
        if h.isCustom || v.isCustom { return true }
        guard alignmentGuidesLive else { return false }
        return children.contains { subtreeHasGuide($0, .h(h)) || subtreeHasGuide($0, .v(v)) }
    }

    /// Cross-axis offsets (from the cross start of the stack's rect) of children that align on `key`, and the extent the aligned block needs. The aligned line sits at the
    /// largest guide value; each child is offset by `line - its guide`.
    func guideLayout(_ children: [Node], _ sizes: [LayoutSize], _ proposals: [ProposedViewSize], _ key: GuideKey, _ axis: StackAxis)
        -> (offsets: [CGFloat], extent: CGFloat, line: CGFloat) {
        let guides = children.indices.map { guideValue(key, of: children[$0], size: sizes[$0], proposal: proposals[$0]) }
        let line = guides.max() ?? 0
        var offsets: [CGFloat] = []
        var extent: CGFloat = 0
        for index in children.indices {
            let offset = line - guides[index]
            offsets.append(offset)
            extent = max(extent, offset + axis.cross(sizes[index]))
        }
        return (offsets, extent, line)
    }

    /// Where a block of aligned children sits in a stack rect that is `slack` larger than the block on the cross axis.
    func guideBlockOffset(_ spec: StackSpec, slack: CGFloat) -> CGFloat {
        switch spec.cross {
        case .start, .firstBaseline, .lastBaseline: return 0
        case .middle: return slack / 2
        case .end: return slack
        }
    }

    /// The guided cross offsets of a stack's children placed in a rect `crossLength` wide on the cross axis; nil when the stack does not align by guides.
    func guidedCrossOffsets(_ children: [Node], _ plan: StackPlan, _ spec: StackSpec, crossLength: CGFloat) -> [CGFloat]? {
        guard let key = guidedKey(children, spec) else { return nil }
        let layout = guideLayout(children, plan.sizes, plan.proposals, key, spec.axis)
        let block = guideBlockOffset(spec, slack: crossLength - layout.extent)
        return layout.offsets.map { $0 + block }
    }

    /// Positions of overlapping children (ZStack) aligned by guides on both axes, and the size of the block. Offsets are from the block's origin.
    func overlapLayout(_ children: [Node], _ sizes: [LayoutSize], _ proposals: [ProposedViewSize], _ spec: StackSpec)
        -> (x: [CGFloat], y: [CGFloat], size: LayoutSize) {
        let hKey = GuideKey.h(spec.alignment.horizontal), vKey = GuideKey.v(spec.alignment.vertical)
        let gx = children.indices.map { guideValue(hKey, of: children[$0], size: sizes[$0], proposal: proposals[$0]) }
        let gy = children.indices.map { guideValue(vKey, of: children[$0], size: sizes[$0], proposal: proposals[$0]) }
        let lineX = gx.max() ?? 0, lineY = gy.max() ?? 0
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        var width: CGFloat = 0, height: CGFloat = 0
        for index in children.indices {
            xs.append(lineX - gx[index])
            ys.append(lineY - gy[index])
            width = max(width, xs[index] + sizes[index].width)
            height = max(height, ys[index] + sizes[index].height)
        }
        return (xs, ys, LayoutSize(width: width, height: height))
    }

    /// Where the aligned block of an overlap sits in a rect with the given horizontal / vertical slack.
    func overlapBlockOffset(_ spec: StackSpec, slackX: CGFloat, slackY: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let x: CGFloat
        switch spec.alignment.horizontal.kind {
        case .leading: x = 0
        case .trailing: x = slackX
        case .center, .custom: x = slackX / 2
        }
        let y: CGFloat
        switch spec.alignment.vertical.kind {
        case .top: y = 0
        case .bottom: y = slackY
        case .center, .firstTextBaseline, .lastTextBaseline, .custom: y = slackY / 2
        }
        return (x, y)
    }

    // MARK: Guide values

    /// The dimensions of `node` laid out at `size` under `proposal`, with the explicit guides of its subtree.
    func dimensions(of node: Node, size: LayoutSize, proposal: ProposedViewSize, explicit: [GuideKey: CGFloat]? = nil) -> ViewDimensions {
        let found = baselines(of: node, proposal)
        return ViewDimensions(width: size.width, height: size.height, firstBaseline: found?.first, lastBaseline: found?.last,
                              explicit: explicit ?? explicitGuides(of: node, size: size, proposal: proposal))
    }

    /// The position of the guide `key` of `node` in the node's own coordinates (from its top-leading corner).
    func guideValue(_ key: GuideKey, of node: Node, size: LayoutSize, proposal: ProposedViewSize) -> CGFloat {
        if !alignmentGuidesLive {
            // no explicit guide can exist: the standard bounds-based guides need no subtree walk
            switch key {
            case .h(let alignment):
                switch alignment.kind {
                case .leading: return 0
                case .center: return size.width / 2
                case .trailing: return size.width
                case .custom: break
                }
            case .v(let alignment):
                switch alignment.kind {
                case .top: return 0
                case .center: return size.height / 2
                case .bottom: return size.height
                default: break
                }
            }
        }
        return dimensions(of: node, size: size, proposal: proposal)[key]
    }

    private func shifted(_ guides: [GuideKey: CGFloat], dx: CGFloat, dy: CGFloat) -> [GuideKey: CGFloat] {
        var out: [GuideKey: CGFloat] = [:]
        for (key, value) in guides {
            switch key {
            case .h: out[key] = value + dx
            case .v: out[key] = value + dy
            }
        }
        return out
    }

    /// The explicit guide values `node` exposes to its container, in the node's coordinates: `.alignmentGuide` modifiers on it and, shifted by where they sit, those of
    /// the views inside it. A stack that aligns on a guide exposes the aligned line for it.
    func explicitGuides(of node: Node, size: LayoutSize, proposal: ProposedViewSize) -> [GuideKey: CGFloat] {
        guard alignmentGuidesLive else { return [:] }
        switch node.kind {
        case .modifier(.alignmentGuide(let spec)):
            guard let child = childNodes(node).first else { return [:] }
            var inner = explicitGuides(of: child, size: size, proposal: proposal)
            let dims = dimensions(of: child, size: size, proposal: proposal, explicit: inner)
            inner[spec.key] = spec.compute(dims)
            return inner
        case .modifier(.padding(let insets)):
            guard let child = childNodes(node).first else { return [:] }
            let innerProposal = ProposedViewSize(width: proposal.width.map { max(0, $0 - insets.horizontal) },
                                                 height: proposal.height.map { max(0, $0 - insets.vertical) })
            let innerSize = LayoutSize(width: max(0, size.width - insets.horizontal), height: max(0, size.height - insets.vertical))
            return shifted(explicitGuides(of: child, size: innerSize, proposal: innerProposal), dx: insets.leading, dy: insets.top)
        case .modifier(.frame(let frame)):
            guard let child = childNodes(node).first else { return [:] }
            let childProposal = ProposedViewSize(width: frame.width ?? proposal.width, height: frame.height ?? proposal.height)
            let childSize = measure(child, childProposal)
            let x = alignmentOffset(frame.alignment.horizontal, available: size.width - childSize.width)
            let y = alignmentOffset(frame.alignment.vertical, available: size.height - childSize.height)
            return shifted(explicitGuides(of: child, size: childSize, proposal: childProposal), dx: x, dy: y)
        case .modifier(.flexibleFrame(let frame)):
            guard let child = childNodes(node).first else { return [:] }
            let childProposal = frame.childProposal(proposal)
            let childSize = measure(child, childProposal)
            let x = alignmentOffset(frame.alignment.horizontal, available: size.width - childSize.width)
            let y = alignmentOffset(frame.alignment.vertical, available: size.height - childSize.height)
            return shifted(explicitGuides(of: child, size: childSize, proposal: childProposal), dx: x, dy: y)
        case .modifier(.fixedSize(let horizontal, let vertical)):
            guard let child = childNodes(node).first else { return [:] }
            let childProposal = fixedProposal(proposal, horizontal, vertical)
            let childSize = measure(child, childProposal)
            return shifted(explicitGuides(of: child, size: childSize, proposal: childProposal),
                           dx: (size.width - childSize.width) / 2, dy: (size.height - childSize.height) / 2)
        case .stack(let spec) where spec.name == "List":
            return [:]
        case .stack(let spec):
            return stackExplicitGuides(childNodes(node), spec, size: size, proposal: proposal)
        case .user, .modifier, .menu:
            let children = childNodes(node)
            if children.count == 1 { return explicitGuides(of: children[0], size: size, proposal: proposal) }
            if children.isEmpty { return [:] }
            return stackExplicitGuides(children, groupStackSpec, size: size, proposal: proposal)
        default:
            return [:]
        }
    }

    private func stackExplicitGuides(_ children: [Node], _ spec: StackSpec, size: LayoutSize, proposal: ProposedViewSize) -> [GuideKey: CGFloat] {
        guard !children.isEmpty else { return [:] }
        var result: [GuideKey: CGFloat] = [:]
        let bounds = LayoutRect(origin: .zero, size: size)
        switch spec.axis {
        case .horizontal, .vertical:
            let frames = stackFrames(children, spec, in: bounds, proposal: proposal)
            for (index, child) in children.enumerated() {
                let rect = frames.rects[index]
                let inner = explicitGuides(of: child, size: rect.size, proposal: frames.plan.proposals[index])
                for (key, value) in shifted(inner, dx: rect.minX, dy: rect.minY) where result[key] == nil { result[key] = value }
            }
            if let key = guidedKey(children, spec) {
                // the aligned line, where every child's guide for the stack's alignment sits
                let rect = frames.rects[0]
                let g = guideValue(key, of: children[0], size: rect.size, proposal: frames.plan.proposals[0])
                switch key {
                case .h: result[key] = rect.minX + g
                case .v: result[key] = rect.minY + g
                }
            }
        case .overlap:
            let rects = overlapFrames(children, spec, in: bounds, proposal: proposal)
            for (index, child) in children.enumerated() {
                let inner = explicitGuides(of: child, size: rects[index].size, proposal: proposal)
                for (key, value) in shifted(inner, dx: rects[index].minX, dy: rects[index].minY) where result[key] == nil { result[key] = value }
            }
            if overlapGuided(children, spec) {
                let rect = rects[0]
                let hKey = GuideKey.h(spec.alignment.horizontal), vKey = GuideKey.v(spec.alignment.vertical)
                result[hKey] = rect.minX + guideValue(hKey, of: children[0], size: rect.size, proposal: proposal)
                result[vKey] = rect.minY + guideValue(vKey, of: children[0], size: rect.size, proposal: proposal)
            }
        case .overlay:
            let baseIndex = spec.baseIsLast ? children.count - 1 : 0
            result = explicitGuides(of: children[baseIndex], size: size, proposal: proposal)
        }
        return result
    }
}

@MainActor
extension Graph {
    /// Turns on guide resolution when a node that needs it is evaluated: an `.alignmentGuide`, or a stack aligned on a custom alignment.
    func noteAlignmentGuides(_ kind: NodeKind) {
        switch kind {
        case .modifier(.alignmentGuide):
            alignmentGuidesLive = true
        case .stack(let spec):
            if spec.customGuide != nil || spec.alignment.horizontal.isCustom || spec.alignment.vertical.isCustom { alignmentGuidesLive = true }
        default:
            break
        }
    }
}
