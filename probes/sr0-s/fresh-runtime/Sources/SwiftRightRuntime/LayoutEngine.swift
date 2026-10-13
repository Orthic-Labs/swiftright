import Foundation

/// Default spacing between stack children, in logical points.
let defaultStackSpacing: CGFloat = 8
/// Default padding length when `padding(_:)` is called without a length, in logical points.
let defaultPaddingLength: CGFloat = 16

enum StackAxis: Sendable {
    case horizontal
    case vertical
    case overlap
    case overlay

    func main(_ size: LayoutSize) -> CGFloat { self == .vertical ? size.height : size.width }
    func cross(_ size: LayoutSize) -> CGFloat { self == .vertical ? size.width : size.height }

    func size(main: CGFloat, cross: CGFloat) -> LayoutSize {
        self == .vertical ? LayoutSize(width: cross, height: main) : LayoutSize(width: main, height: cross)
    }

    func proposal(main: CGFloat?, cross: CGFloat?) -> ProposedViewSize {
        self == .vertical ? ProposedViewSize(width: cross, height: main) : ProposedViewSize(width: main, height: cross)
    }

    func mainLimit(_ proposal: ProposedViewSize) -> CGFloat? {
        finiteLength(self == .vertical ? proposal.height : proposal.width)
    }

    func crossLimit(_ proposal: ProposedViewSize) -> CGFloat? {
        finiteLength(self == .vertical ? proposal.width : proposal.height)
    }
}

enum CrossAlignment: Sendable {
    case start
    case middle
    case end
}

struct StackSpec: Sendable, Equatable {
    let name: String
    let axis: StackAxis
    let cross: CrossAlignment
    let alignment: Alignment
    let spacing: CGFloat
    /// List-style: the stack takes the full finite cross proposal.
    let fillsCross: Bool
    /// Keeps `@State` of keyed rows removed from this container, so a reinserted row with the same
    /// id gets its old state back. Only List does this on the recorded macOS 27 oracle (SR0-O F3).
    var retainsRemovedRowState = false

    init(name: String, axis: StackAxis, cross: CrossAlignment, alignment: Alignment = .center,
         spacing: CGFloat, fillsCross: Bool, retainsRemovedRowState: Bool = false) {
        self.name = name
        self.axis = axis
        self.cross = cross
        self.alignment = alignment
        self.spacing = spacing
        self.fillsCross = fillsCross
        self.retainsRemovedRowState = retainsRemovedRowState
    }
}

/// Result of distributing a stack's main axis under one proposal.
struct StackPlan {
    let children: [Node]
    let sizes: [LayoutSize]
    /// The proposal each child was sized under; placement passes it back unchanged.
    let proposals: [ProposedViewSize]
    let size: LayoutSize
}

let groupStackSpec = StackSpec(name: "Group", axis: .vertical, cross: .start, spacing: 0, fillsCross: false)

/// The layout engine. Geometry is computed in logical points and snapped to the physical pixel
/// grid at placement. Text measurements are memoized per node by wrap width and text content.
@MainActor
extension Graph {
    func layoutRoot() {
        guard let root else { return }
        let size = measure(root, rootProposal)
        place(root, in: LayoutRect(origin: .zero, size: size), proposal: rootProposal)
    }

    /// Size of `node` under `proposal`. A result is kept on the node until the node or a descendant is evaluated again, so a
    /// layout pass asks each subtree once per distinct proposal instead of once per query (stacks and layouts query a child
    /// several times).
    func measure(_ node: Node, _ proposal: ProposedViewSize) -> LayoutSize {
        if let cached = node.sizeCache[proposal] { return cached }
        let size = computeSize(node, proposal)
        if node.sizeCache.count >= 16 { node.sizeCache.removeAll(keepingCapacity: true) }
        node.sizeCache[proposal] = size
        return size
    }

    private func computeSize(_ node: Node, _ proposal: ProposedViewSize) -> LayoutSize {
        switch node.kind {
        case .text(let string):
            return measureText(node, string, width: proposal.width)
        case .textField:
            return measureText(node, node.textInput?.display ?? "", width: nil)
        case .textEditor:
            // Greedy like SwiftUI TextEditor: takes each finite proposal axis, else the measured text.
            let measured = measureText(node, node.textInput?.display ?? "", width: proposal.width)
            return LayoutSize(
                width: finiteLength(proposal.width) ?? measured.width,
                height: finiteLength(proposal.height) ?? measured.height
            )
        case .image(let spec):
            let ideal = imageIntrinsicSize(spec.reference)
            guard spec.sizing.isResizable else { return ideal }
            if spec.sizing.scalesToFit, ideal.width > 0, ideal.height > 0 {
                let widthScale = finiteLength(proposal.width).map { $0 / ideal.width }
                let heightScale = finiteLength(proposal.height).map { $0 / ideal.height }
                let scale: CGFloat
                switch (widthScale, heightScale) {
                case let (width?, height?): scale = min(width, height)
                case let (width?, nil): scale = width
                case let (nil, height?): scale = height
                case (nil, nil): return ideal
                }
                return LayoutSize(width: ideal.width * scale, height: ideal.height * scale)
            }
            return LayoutSize(
                width: finiteLength(proposal.width) ?? ideal.width,
                height: finiteLength(proposal.height) ?? ideal.height
            )
        case .color:
            return LayoutSize(width: finiteLength(proposal.width) ?? 0, height: finiteLength(proposal.height) ?? 0)
        case .shape:
            return LayoutSize(width: finiteLength(proposal.width) ?? 10, height: finiteLength(proposal.height) ?? 10)
        case .divider:
            return LayoutSize(width: finiteLength(proposal.width) ?? 0, height: dividerThickness)
        case .spacer:
            return .zero
        case .modifier(.padding(let insets)):
            let inner = ProposedViewSize(
                width: proposal.width.map { max(0, $0 - insets.horizontal) },
                height: proposal.height.map { max(0, $0 - insets.vertical) }
            )
            let inside = childNodes(node).first.map { measure($0, inner) } ?? .zero
            return LayoutSize(width: inside.width + insets.horizontal, height: inside.height + insets.vertical)
        case .modifier(.frame(let frame)):
            let childProposal = ProposedViewSize(
                width: frame.width ?? proposal.width,
                height: frame.height ?? proposal.height
            )
            let inside = childNodes(node).first.map { measure($0, childProposal) } ?? .zero
            return LayoutSize(width: frame.width ?? inside.width, height: frame.height ?? inside.height)
        case .modifier(.flexibleFrame(let frame)):
            let childProposal = frame.childProposal(proposal)
            let inside = childNodes(node).first.map { measure($0, childProposal) } ?? .zero
            return frame.frameSize(for: inside, proposal: proposal)
        case .stack(let spec):
            return stackPlan(childNodes(node), spec, proposal).size
        case .layout(let spec):
            return spec.size(proposal, subviews(of: node), &node.layoutStorage)
        case .scroll:
            // Takes the proposal on each axis; without one, the content's ideal size.
            let width = finiteLength(proposal.width)
            let content = measureGroup(node, ProposedViewSize(width: width, height: nil))
            return LayoutSize(width: width ?? content.width, height: finiteLength(proposal.height) ?? content.height)
        case .scrollView(let configuration):
            let width = finiteLength(proposal.width)
            let height = finiteLength(proposal.height)
            let contentProposal = ProposedViewSize(
                width: configuration.axes.contains(.horizontal) ? nil : width,
                height: configuration.axes.contains(.vertical) ? nil : height
            )
            let content = measureGroup(node, contentProposal)
            return LayoutSize(width: width ?? content.width, height: height ?? content.height)
        case .user, .button, .modifier, .toggle, .menu:
            return measureGroup(node, proposal)
        }
    }

    func place(_ node: Node, in rect: LayoutRect, proposal: ProposedViewSize) {
        node.frame = snapToPixelGrid(rect, scale: scale)
        switch node.kind {
        case .text, .textField, .textEditor, .spacer, .image, .color, .divider, .shape:
            break
        case .modifier(.padding(let insets)):
            guard let child = childNodes(node).first else { return }
            let inner = LayoutRect(
                x: rect.minX + insets.leading,
                y: rect.minY + insets.top,
                width: rect.width - insets.horizontal,
                height: rect.height - insets.vertical
            )
            let innerProposal = ProposedViewSize(
                width: proposal.width.map { max(0, $0 - insets.horizontal) },
                height: proposal.height.map { max(0, $0 - insets.vertical) }
            )
            placeChild(child, in: inner, within: node, bounds: rect, proposal: innerProposal)
        case .modifier(.frame(let frame)):
            guard let child = childNodes(node).first else { return }
            let childProposal = ProposedViewSize(
                width: frame.width ?? proposal.width,
                height: frame.height ?? proposal.height
            )
            let childSize = measure(child, childProposal)
            let x = alignmentOffset(frame.alignment.horizontal, available: rect.width - childSize.width)
            let y = alignmentOffset(frame.alignment.vertical, available: rect.height - childSize.height)
            let inner = LayoutRect(
                x: rect.minX + x,
                y: rect.minY + y,
                width: childSize.width,
                height: childSize.height
            )
            placeChild(child, in: inner, within: node, bounds: rect, proposal: childProposal)
        case .modifier(.flexibleFrame(let frame)):
            guard let child = childNodes(node).first else { return }
            let childProposal = frame.childProposal(proposal)
            let childSize = measure(child, childProposal)
            let x = alignmentOffset(frame.alignment.horizontal, available: rect.width - childSize.width)
            let y = alignmentOffset(frame.alignment.vertical, available: rect.height - childSize.height)
            let inner = LayoutRect(
                x: rect.minX + x,
                y: rect.minY + y,
                width: childSize.width,
                height: childSize.height
            )
            placeChild(child, in: inner, within: node, bounds: rect, proposal: childProposal)
        case .stack(let spec):
            placeStack(childNodes(node), spec, in: rect, proposal: proposal, mirrored: mirrors(node))
        case .layout(let spec):
            spec.place(rect, proposal, subviews(of: node, mirroringIn: mirrors(node) ? rect : nil), &node.layoutStorage)
        case .scroll:
            // The content is laid out at its ideal height and shifted up by the scroll offset. The offset
            // is clamped so the content never scrolls past its own bounds.
            let content = measureGroup(node, ProposedViewSize(width: rect.width, height: nil))
            let maxOffset = max(0, content.height - rect.height)
            node.scrollOffset = min(max(0, node.scrollOffset), maxOffset)
            let contentRect = LayoutRect(x: rect.minX, y: rect.minY - node.scrollOffset, width: rect.width, height: content.height)
            placeGroup(node, in: contentRect, proposal: ProposedViewSize(width: rect.width, height: nil))
        case .scrollView(let configuration):
            let contentProposal = ProposedViewSize(
                width: configuration.axes.contains(.horizontal) ? nil : rect.width,
                height: configuration.axes.contains(.vertical) ? nil : rect.height
            )
            let content = measureGroup(node, contentProposal)
            let maxX = configuration.axes.contains(.horizontal) ? max(0, content.width - rect.width) : 0
            let maxY = configuration.axes.contains(.vertical) ? max(0, content.height - rect.height) : 0
            let offsetX = min(max(0, node.scrollOffsetX ?? 0), maxX)
            let offsetY = min(max(0, node.scrollOffsetY ?? 0), maxY)
            node.scrollOffsetX = offsetX
            node.scrollOffsetY = offsetY
            let contentRect = LayoutRect(
                x: rect.minX - offsetX,
                y: rect.minY - offsetY,
                width: configuration.axes.contains(.horizontal) ? content.width : rect.width,
                height: configuration.axes.contains(.vertical) ? content.height : rect.height
            )
            placeGroup(node, in: contentRect, proposal: contentProposal)
        case .user, .button, .modifier, .toggle, .menu:
            placeGroup(node, in: rect, proposal: proposal)
        }
    }

    private func placeGroup(_ node: Node, in rect: LayoutRect, proposal: ProposedViewSize) {
        let children = childNodes(node)
        if children.count == 1 {
            placeChild(children[0], in: rect, within: node, bounds: rect, proposal: proposal)
        } else if children.count > 1 {
            placeStack(children, groupStackSpec, in: rect, proposal: proposal, mirrored: mirrors(node))
        }
    }

    func stackPlan(_ children: [Node], _ spec: StackSpec, _ proposal: ProposedViewSize) -> StackPlan {
        if spec.axis == .overlap { return overlapPlan(children, spec, proposal) }
        if spec.axis == .overlay { return overlayPlan(children, spec, proposal) }
        let axis = spec.axis
        let spacingTotal = spec.spacing * CGFloat(max(0, children.count - 1))
        let crossLimit = axis.crossLimit(proposal)
        let minLengths: [CGFloat?] = children.map { spacerLength($0, axis) }
        let fixed: [LayoutSize?] = children.map { fixedStackSize($0, axis, crossLimit) }
        var sizes = Array(repeating: LayoutSize.zero, count: children.count)
        var proposals = Array(repeating: ProposedViewSize.unspecified, count: children.count)

        if let limit = axis.mainLimit(proposal) {
            // Least flexible first, so that flexible children (spacers) receive what remains.
            let available = max(0, limit - spacingTotal)
            let flex: [CGFloat] = children.indices.map { index in
                if minLengths[index] != nil { return CGFloat.infinity }
                let least = axis.main(measure(children[index], axis.proposal(main: 0, cross: crossLimit)))
                let most = axis.main(measure(children[index], axis.proposal(main: CGFloat.infinity, cross: crossLimit)))
                return most - least
            }
            let order = children.indices.sorted { (flex[$0], $0) < (flex[$1], $1) }
            var remaining = available
            var left = children.count
            for index in order {
                let share = max(0, remaining / CGFloat(left))
                let proposal = axis.proposal(main: share, cross: crossLimit)
                let size: LayoutSize
                if let minLength = minLengths[index] {
                    let measured = measure(children[index], proposal)
                    size = axis.size(main: max(minLength, share), cross: axis.cross(measured))
                } else if let fixedSize = fixed[index] {
                    size = fixedSize
                } else {
                    size = measure(children[index], proposal)
                }
                sizes[index] = size
                proposals[index] = proposal
                remaining -= axis.main(size)
                left -= 1
            }
        } else {
            // No main-axis limit: every child reports its ideal size; spacers collapse to their minimum.
            for index in children.indices {
                let proposal = axis.proposal(main: nil, cross: crossLimit)
                if let minLength = minLengths[index] {
                    let measured = measure(children[index], proposal)
                    sizes[index] = axis.size(main: minLength, cross: axis.cross(measured))
                } else if let fixedSize = fixed[index] {
                    sizes[index] = fixedSize
                } else {
                    sizes[index] = measure(children[index], proposal)
                }
                proposals[index] = proposal
            }
        }

        let contentCross = sizes.map(axis.cross).max() ?? 0
        let cross = spec.fillsCross ? (crossLimit ?? contentCross) : contentCross
        let main = sizes.reduce(0) { $0 + axis.main($1) } + spacingTotal
        return StackPlan(children: children, sizes: sizes, proposals: proposals, size: axis.size(main: main, cross: cross))
    }

    private func placeStack(_ children: [Node], _ spec: StackSpec, in rect: LayoutRect, proposal: ProposedViewSize, mirrored: Bool) {
        if spec.axis == .overlap {
            placeOverlap(children, spec, in: rect, proposal: proposal, mirrored: mirrored)
            return
        }
        if spec.axis == .overlay {
            placeOverlay(children, spec, in: rect, proposal: proposal, mirrored: mirrored)
            return
        }
        let axis = spec.axis
        let plan = stackPlan(children, spec, proposal)
        let crossLength = axis.cross(rect.size)
        var offset = axis == .vertical ? rect.minY : rect.minX
        for (index, child) in children.enumerated() {
            let size = plan.sizes[index]
            let slack = crossLength - axis.cross(size)
            let crossOffset: CGFloat
            switch spec.cross {
            case .start: crossOffset = 0
            case .middle: crossOffset = slack / 2
            case .end: crossOffset = slack
            }
            let origin = axis == .vertical
                ? LayoutPoint(x: rect.minX + crossOffset, y: offset)
                : LayoutPoint(x: offset, y: rect.minY + crossOffset)
            place(child, in: mirroredRect(LayoutRect(origin: origin, size: size), in: rect, if: mirrored), proposal: plan.proposals[index])
            offset += axis.main(size) + spec.spacing
        }
    }


    private func overlapPlan(_ children: [Node], _ spec: StackSpec, _ proposal: ProposedViewSize) -> StackPlan {
        let sizes = children.map { measure($0, proposal) }
        let width = sizes.map(\.width).max() ?? 0
        let height = sizes.map(\.height).max() ?? 0
        let childProposals = Array(repeating: proposal, count: children.count)
        return StackPlan(children: children, sizes: sizes, proposals: childProposals,
                         size: LayoutSize(width: width, height: height))
    }

    private func overlayPlan(_ children: [Node], _ spec: StackSpec, _ proposal: ProposedViewSize) -> StackPlan {
        guard let base = children.first else {
            return StackPlan(children: [], sizes: [], proposals: [], size: .zero)
        }
        let baseSize = measure(base, proposal)
        let overlayProposal = ProposedViewSize(baseSize)
        let sizes = [baseSize] + children.dropFirst().map { measure($0, overlayProposal) }
        let proposals = [proposal] + Array(repeating: overlayProposal, count: children.count - 1)
        return StackPlan(children: children, sizes: sizes, proposals: proposals, size: baseSize)
    }

    private func placeOverlay(_ children: [Node], _ spec: StackSpec, in rect: LayoutRect, proposal: ProposedViewSize, mirrored: Bool) {
        guard let base = children.first else { return }
        let plan = overlayPlan(children, spec, proposal)
        place(base, in: mirroredRect(rect, in: rect, if: mirrored), proposal: plan.proposals[0])
        for index in 1..<children.count {
            let child = children[index]
            let size = plan.sizes[index]
            let xSlack = rect.width - size.width
            let ySlack = rect.height - size.height
            let x: CGFloat
            switch spec.alignment.horizontal.kind {
            case .leading: x = rect.minX
            case .center: x = rect.minX + xSlack / 2
            case .trailing: x = rect.minX + xSlack
            }
            let y: CGFloat
            switch spec.alignment.vertical.kind {
            case .top: y = rect.minY
            case .center: y = rect.minY + ySlack / 2
            case .bottom: y = rect.minY + ySlack
            }
            place(child, in: mirroredRect(LayoutRect(x: x, y: y, width: size.width, height: size.height), in: rect, if: mirrored), proposal: plan.proposals[index])
        }
    }

    private func placeOverlap(_ children: [Node], _ spec: StackSpec, in rect: LayoutRect, proposal: ProposedViewSize, mirrored: Bool) {
        for child in children {
            let size = measure(child, proposal)
            let xSlack = rect.width - size.width
            let ySlack = rect.height - size.height
            let x: CGFloat
            switch spec.alignment.horizontal.kind {
            case .leading: x = rect.minX
            case .center: x = rect.minX + xSlack / 2
            case .trailing: x = rect.minX + xSlack
            }
            let y: CGFloat
            switch spec.alignment.vertical.kind {
            case .top: y = rect.minY
            case .center: y = rect.minY + ySlack / 2
            case .bottom: y = rect.minY + ySlack
            }
            place(child, in: mirroredRect(LayoutRect(x: x, y: y, width: size.width, height: size.height), in: rect, if: mirrored), proposal: proposal)
        }
    }

    private func measureGroup(_ node: Node, _ proposal: ProposedViewSize) -> LayoutSize {
        let children = childNodes(node)
        if children.count == 1 { return measure(children[0], proposal) }
        if children.isEmpty { return .zero }
        return stackPlan(children, groupStackSpec, proposal).size
    }

    /// A divider's size in a stack: thin on the main axis, filling the cross axis.
    private func fixedStackSize(_ node: Node, _ axis: StackAxis, _ crossLimit: CGFloat?) -> LayoutSize? {
        guard case .divider = node.kind else { return nil }
        return axis.size(main: dividerThickness, cross: crossLimit ?? 0)
    }

    private func alignmentOffset(_ alignment: HorizontalAlignment, available: CGFloat) -> CGFloat {
        switch alignment.kind {
        case .leading: return 0
        case .center: return available / 2
        case .trailing: return available
        }
    }

    private func alignmentOffset(_ alignment: VerticalAlignment, available: CGFloat) -> CGFloat {
        switch alignment.kind {
        case .top: return 0
        case .center: return available / 2
        case .bottom: return available
        }
    }

    /// A spacer's minimum length, seen through single-child wrappers; nil for other views.
    private func spacerLength(_ node: Node, _ axis: StackAxis) -> CGFloat? {
        if case .spacer(let minLength) = node.kind { return minLength }
        if case .modifier(.frame(let frame)) = node.kind {
            let fixesMainAxis = axis == .horizontal ? frame.width != nil : frame.height != nil
            if fixesMainAxis { return nil }
        }
        if case .modifier(.flexibleFrame(let frame)) = node.kind {
            let minimum = axis == .horizontal ? frame.minWidth : frame.minHeight
            let maximum = axis == .horizontal ? frame.maxWidth : frame.maxHeight
            // A finite main-axis maximum makes this a bounded flexible child, not an unbounded
            // spacer. Let normal stack proposal distribution measure it so its maximum is honored.
            if let maximum, maximum.isFinite { return nil }
            guard node.kind.passesThrough else { return nil }
            let children = childNodes(node)
            guard children.count == 1, let childMinimum = spacerLength(children[0], axis) else { return nil }
            // Infinite maximums preserve spacer flexibility; a main-axis minimum raises its floor.
            return max(childMinimum, minimum ?? 0)
        }
        guard node.kind.passesThrough else { return nil }
        let children = childNodes(node)
        return children.count == 1 ? spacerLength(children[0], axis) : nil
    }

    private func measureText(_ node: Node, _ string: String, width: CGFloat?) -> LayoutSize {
        let wrapWidth = finiteLength(width)
        let font = node.environment.font ?? Font(id: "body")
        let lineLimit: Int?
        if case .text = node.kind { lineLimit = node.environment.lineLimit } else { lineLimit = nil }
        if node.memoText != string || node.memoFont != font || node.memoLineLimit != lineLimit {
            node.memoText = string
            node.memoFont = font
            node.memoLineLimit = lineLimit
            node.memo.removeAll()
        }
        if let cached = node.memo[wrapWidth] { return cached }
        let request = TextMeasureRequest(
            text: string, fontID: font.id, proposedWidth: wrapWidth, scale: scale,
            fontMetadata: font.metadata, lineLimit: lineLimit
        )
        let size = measurer.measure(request).size
        node.memo[wrapWidth] = size
        return size
    }

    func childNodes(_ node: Node) -> [Node] {
        if case .toggle = node.kind, node.environment.labelsHidden { return [] }
        return node.childNodes
    }

    func subviews(of node: Node, mirroringIn bounds: LayoutRect? = nil) -> Subviews {
        Subviews(childNodes(node).map { Subview(graph: self, node: $0, mirrorBounds: bounds) })
    }

    // MARK: Layout direction
    //
    // SwiftUI semantics: containers compute positions as if left-to-right (leading = left); under a
    // right-to-left environment the system mirrors each child's frame within its container's bounds,
    // x' = minX + maxX - (x + width). Sizes never change and text glyph order is not touched. The
    // direction is the one in effect at the container (its own environment, which includes its own
    // `.environment(\.layoutDirection, _)` override), so a nested left-to-right override un-flips its subtree.

    func mirrors(_ node: Node) -> Bool {
        node.environment.layoutDirection == .rightToLeft
    }

    func mirroredRect(_ rect: LayoutRect, in bounds: LayoutRect, if mirrored: Bool) -> LayoutRect {
        guard mirrored else { return rect }
        return LayoutRect(x: bounds.minX + bounds.maxX - (rect.minX + rect.width), y: rect.minY,
                          width: rect.width, height: rect.height)
    }

    private func placeChild(_ child: Node, in rect: LayoutRect, within node: Node, bounds: LayoutRect, proposal: ProposedViewSize) {
        place(child, in: mirroredRect(rect, in: bounds, if: mirrors(node)), proposal: proposal)
    }
}
