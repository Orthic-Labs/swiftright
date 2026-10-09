import Foundation

/// Default spacing between stack children, in logical points.
let defaultStackSpacing: CGFloat = 8
/// Default padding length when `padding(_:)` is called without a length, in logical points.
let defaultPaddingLength: CGFloat = 16

enum StackAxis: Sendable {
    case horizontal
    case vertical

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

struct StackSpec: Sendable {
    let name: String
    let axis: StackAxis
    let cross: CrossAlignment
    let spacing: CGFloat
    /// List-style: the stack takes the full finite cross proposal.
    let fillsCross: Bool
    /// Keeps `@State` of keyed rows removed from this container, so a reinserted row with the same
    /// id gets its old state back. Only List does this on the recorded macOS 27 oracle (SR0-O F3).
    var retainsRemovedRowState = false
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

    func measure(_ node: Node, _ proposal: ProposedViewSize) -> LayoutSize {
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
        case .image(let reference):
            return imageIntrinsicSize(reference)
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
        case .stack(let spec):
            return stackPlan(childNodes(node), spec, proposal).size
        case .layout(let spec):
            return spec.size(proposal, subviews(of: node), &node.layoutStorage)
        case .scroll:
            // Takes the proposal on each axis; without one, the content's ideal size.
            let width = finiteLength(proposal.width)
            let content = measureGroup(node, ProposedViewSize(width: width, height: nil))
            return LayoutSize(width: width ?? content.width, height: finiteLength(proposal.height) ?? content.height)
        case .user, .button, .modifier, .toggle, .menu:
            return measureGroup(node, proposal)
        }
    }

    func place(_ node: Node, in rect: LayoutRect, proposal: ProposedViewSize) {
        node.frame = snapToPixelGrid(rect, scale: scale)
        switch node.kind {
        case .text, .textField, .textEditor, .spacer, .image, .divider:
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
            place(child, in: inner, proposal: innerProposal)
        case .stack(let spec):
            placeStack(childNodes(node), spec, in: rect, proposal: proposal)
        case .layout(let spec):
            spec.place(rect, proposal, subviews(of: node), &node.layoutStorage)
        case .scroll:
            // The content is laid out at its ideal height and shifted up by the scroll offset. The offset
            // is clamped so the content never scrolls past its own bounds.
            let content = measureGroup(node, ProposedViewSize(width: rect.width, height: nil))
            let maxOffset = max(0, content.height - rect.height)
            node.scrollOffset = min(max(0, node.scrollOffset), maxOffset)
            let contentRect = LayoutRect(x: rect.minX, y: rect.minY - node.scrollOffset, width: rect.width, height: content.height)
            placeGroup(node, in: contentRect, proposal: ProposedViewSize(width: rect.width, height: nil))
        case .user, .button, .modifier, .toggle, .menu:
            placeGroup(node, in: rect, proposal: proposal)
        }
    }

    private func placeGroup(_ node: Node, in rect: LayoutRect, proposal: ProposedViewSize) {
        let children = childNodes(node)
        if children.count == 1 {
            place(children[0], in: rect, proposal: proposal)
        } else if children.count > 1 {
            placeStack(children, groupStackSpec, in: rect, proposal: proposal)
        }
    }

    func stackPlan(_ children: [Node], _ spec: StackSpec, _ proposal: ProposedViewSize) -> StackPlan {
        let axis = spec.axis
        let spacingTotal = spec.spacing * CGFloat(max(0, children.count - 1))
        let crossLimit = axis.crossLimit(proposal)
        let minLengths: [CGFloat?] = children.map { spacerLength($0) }
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
                    size = axis.size(main: max(minLength, share), cross: 0)
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
                    sizes[index] = axis.size(main: minLength, cross: 0)
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

    private func placeStack(_ children: [Node], _ spec: StackSpec, in rect: LayoutRect, proposal: ProposedViewSize) {
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
            place(child, in: LayoutRect(origin: origin, size: size), proposal: plan.proposals[index])
            offset += axis.main(size) + spec.spacing
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

    /// A spacer's minimum length, seen through single-child wrappers; nil for other views.
    private func spacerLength(_ node: Node) -> CGFloat? {
        if case .spacer(let minLength) = node.kind { return minLength }
        guard node.kind.passesThrough else { return nil }
        let children = childNodes(node)
        return children.count == 1 ? spacerLength(children[0]) : nil
    }

    private func measureText(_ node: Node, _ string: String, width: CGFloat?) -> LayoutSize {
        let wrapWidth = finiteLength(width)
        let fontID = node.environment.font?.id ?? "body"
        if node.memoText != string || node.memoFont != fontID {
            node.memoText = string
            node.memoFont = fontID
            node.memo.removeAll()
        }
        if let cached = node.memo[wrapWidth] { return cached }
        let request = TextMeasureRequest(text: string, fontID: fontID, proposedWidth: wrapWidth, scale: scale)
        let size = measurer.measure(request).size
        node.memo[wrapWidth] = size
        return size
    }

    func childNodes(_ node: Node) -> [Node] {
        node.children.compactMap { nodes[$0] }
    }

    func subviews(of node: Node) -> Subviews {
        Subviews(childNodes(node).map { Subview(graph: self, node: $0) })
    }
}
