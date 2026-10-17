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
    /// HStack only: the children's first / last text baselines line up.
    case firstBaseline
    case lastBaseline
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
    /// The spacing was not given (`spacing: nil`): the distance next to a Spacer is then 0, not the default spacing (measured on macOS 27: `HStack { 40 pt; Spacer(minLength: 0); 40 pt }`
    /// in an 80 pt frame leaves no gap, while two rectangles are 8 pt apart; an explicit `spacing:` applies on both sides of a Spacer).
    var spacingIsDefault = false

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
    /// The distance after each child (empty for the overlay and overlap plans).
    var gaps: [CGFloat] = []
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
            return measureText(node, node.environment.textCase?.apply(string) ?? string, width: proposal.width)
        case .textField:
            return measureTextField(node, proposal)
        case .textEditor:
            // Greedy like SwiftUI TextEditor: takes each finite proposal axis, else the measured text.
            let measured = measureText(node, node.textInput?.display ?? "", width: proposal.width)
            return LayoutSize(
                width: finiteLength(proposal.width) ?? measured.width,
                height: finiteLength(proposal.height) ?? measured.height
            )
        case .image(let spec):
            var ideal = imageIntrinsicSize(spec.reference)
            var pixelSized = false
            if case .pixels(let image, let scale) = spec.reference {   // intrinsic size is the pixel size in points; no host hook
                ideal = LayoutSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
                pixelSized = true
            }
            guard spec.sizing.isResizable else { return pixelSized ? ideal : (imageFontIntrinsicSize(spec.reference, node.environment.font) ?? ideal) }
            if spec.sizing.scalesToFit || spec.sizing.scalesToFill {
                let intrinsic = pixelSized ? ideal : (imageFitIntrinsicSize(spec.reference) ?? ideal)
                var ideal = intrinsic
                if let ratio = spec.sizing.aspectRatio { ideal = LayoutSize(width: ratio, height: 1) }   // only the aspect matters when a ratio is given
                guard ideal.width > 0, ideal.height > 0 else {
                    return LayoutSize(width: finiteLength(proposal.width) ?? ideal.width,
                                      height: finiteLength(proposal.height) ?? ideal.height)
                }
                let widthScale = finiteLength(proposal.width).map { $0 / ideal.width }
                let heightScale = finiteLength(proposal.height).map { $0 / ideal.height }
                let scale: CGFloat
                switch (widthScale, heightScale) {
                case let (width?, height?): scale = spec.sizing.scalesToFill ? max(width, height) : min(width, height)
                case let (width?, nil): scale = width
                case let (nil, height?): scale = height
                case (nil, nil): return intrinsic
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
            // A Divider is a thin rule across the axis its enclosing stack does NOT lay out along (vertical in an HStack, whether or not a frame wraps it).
            if dividerIsVertical(node) { return LayoutSize(width: dividerThickness, height: finiteLength(proposal.height) ?? 0) }
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
        case .modifier(.fixedSize(let horizontal, let vertical)):
            // Ideal size on the fixed axes (nothing proposed), the offer on the others (decision L7).
            return childNodes(node).first.map { measure($0, fixedProposal(proposal, horizontal, vertical)) } ?? .zero
        case .stack(let spec) where spec.name == "List":
            return LayoutSize(width: finiteLength(proposal.width) ?? 0, height: finiteLength(proposal.height) ?? 0)
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
        case .toggle:
            return measureToggle(node, proposal)
        case .slider:
            return measureSlider(proposal)
        case .button:
            return measureButton(node, proposal)
        case .user, .modifier, .menu:
            return measureGroup(node, proposal)
        }
    }

    /// The proposal a `.fixedSize` view passes down: nil (ideal) on each fixed axis.
    private func fixedProposal(_ proposal: ProposedViewSize, _ horizontal: Bool, _ vertical: Bool) -> ProposedViewSize {
        ProposedViewSize(width: horizontal ? nil : proposal.width, height: vertical ? nil : proposal.height)
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
        case .modifier(.fixedSize(let horizontal, let vertical)):
            guard let child = childNodes(node).first else { return }
            let childProposal = fixedProposal(proposal, horizontal, vertical)
            let childSize = measure(child, childProposal)
            // The child keeps its ideal size and sits centred in the frame it was given (SwiftUI: a fixed-size view overflows its parent's frame on both sides).
            let inner = LayoutRect(x: rect.minX + (rect.width - childSize.width) / 2, y: rect.minY + (rect.height - childSize.height) / 2,
                                   width: childSize.width, height: childSize.height)
            placeChild(child, in: inner, within: node, bounds: rect, proposal: childProposal)
        case .stack(let spec) where spec.name == "List":
            placeList(node, in: rect)
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
            // A scroll view that was never scrolled starts where `.defaultScrollAnchor` puts it (the leading/top edge without one).
            let anchor = node.environment.defaultScrollAnchor
            let offsetX = min(max(0, node.scrollOffsetX ?? (anchor.map { maxX * $0.x } ?? 0)), maxX)
            let offsetY = min(max(0, node.scrollOffsetY ?? (anchor.map { maxY * $0.y } ?? 0)), maxY)
            node.scrollOffsetX = offsetX
            node.scrollOffsetY = offsetY
            let contentRect = LayoutRect(
                x: rect.minX - offsetX,
                y: rect.minY - offsetY,
                width: configuration.axes.contains(.horizontal) ? content.width : rect.width,
                height: configuration.axes.contains(.vertical) ? content.height : rect.height
            )
            placeGroup(node, in: contentRect, proposal: contentProposal)
        case .toggle:
            placeToggle(node, in: rect, proposal: proposal)
        case .slider:
            placeSlider(node, in: rect)
        case .button:
            placeButton(node, in: rect, proposal: proposal)
        case .user, .modifier, .menu:
            placeGroup(node, in: rect, proposal: proposal)
        }
    }

    // MARK: Button

    /// A Button is its label inside the push button macOS draws for the bordered looks (the label plus `ButtonMetrics.padding`, the label centred in the
    /// button), or the label alone for `.borderless` and `.plain`.
    private func buttonPadding(_ node: Node) -> LayoutSize {
        ButtonMetrics.padding(for: ButtonLook(style: node.environment.buttonStyleMetadata, isDefaultAction: false))
    }

    private func measureButton(_ node: Node, _ proposal: ProposedViewSize) -> LayoutSize {
        let padding = buttonPadding(node)
        let inner = ProposedViewSize(width: proposal.width.map { max(0, $0 - 2 * padding.width) }, height: proposal.height.map { max(0, $0 - 2 * padding.height) })
        let label = measureGroup(node, inner)
        return LayoutSize(width: label.width + 2 * padding.width, height: label.height + 2 * padding.height)
    }

    private func placeButton(_ node: Node, in rect: LayoutRect, proposal: ProposedViewSize) {
        let padding = buttonPadding(node)
        let inner = LayoutRect(x: rect.minX + padding.width, y: rect.minY + padding.height,
                               width: max(0, rect.width - 2 * padding.width), height: max(0, rect.height - 2 * padding.height))
        let innerProposal = ProposedViewSize(width: proposal.width.map { max(0, $0 - 2 * padding.width) }, height: proposal.height.map { max(0, $0 - 2 * padding.height) })
        placeGroup(node, in: inner, proposal: innerProposal)
    }

    // MARK: List

    /// Rows top to bottom, each `ListMetrics.rowHeight` tall with its content centred and inset from the leading edge (see `ListMetrics`). Rows below the
    /// List's bottom edge are laid out and clipped by the host; there is no scrolling.
    private func placeList(_ node: Node, in rect: LayoutRect) {
        let look = ListLook(style: node.environment.listStyleMetadata)
        let inset = ListMetrics.contentInset(look)
        let children = childNodes(node)
        // Overflow decides the gutter, so it is read from the rows at the full width first. A row that wraps at the narrower width could change height;
        // this pass does not re-decide, so a wrap that crosses the viewport edge is the one case not measured.
        let fullProposal = ProposedViewSize(width: max(0, rect.width - 2 * inset), height: nil)
        let heights = children.map { ListMetrics.rowHeight(forContent: measure($0, fullProposal).height) }
        let gutter = ListMetrics.trailingGutter(look, overflows: ListMetrics.overflows(look, rowHeights: heights, viewportHeight: rect.height))
        // A row spans the list less the trailing scroller gutter, so the content's proposal is the row's width less the two insets.
        let proposal = ProposedViewSize(width: max(0, rect.width - gutter - 2 * inset), height: nil)
        var y = rect.minY + ListMetrics.topInset(look)
        for child in children {
            let size = measure(child, proposal)
            let rowHeight = ListMetrics.rowHeight(forContent: size.height)
            let content = LayoutRect(x: rect.minX + inset, y: y + (rowHeight - size.height) / 2, width: size.width, height: size.height)
            placeChild(child, in: content, within: node, bounds: rect, proposal: proposal)
            y += rowHeight
        }
    }

    // MARK: Toggle

    /// A Toggle with drawn artwork (`ToggleMetrics`) is its label and the control side by side (the switch trails its label, the checkbox
    /// leads it; mirrored under right-to-left), both centred vertically. Without a label (`labelsHidden`) it is the control alone. A style without
    /// drawn artwork lays out as its label alone, as before.
    private func toggleArtwork(_ node: Node) -> ToggleArtwork? {
        ToggleMetrics.artwork(forStyle: node.environment.toggleStyleMetadata)
    }

    private func toggleLabelProposal(_ artwork: ToggleArtwork, _ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width.map { max(0, $0 - artwork.controlSize.width - artwork.labelSpacing) }, height: proposal.height)
    }

    private func measureToggle(_ node: Node, _ proposal: ProposedViewSize) -> LayoutSize {
        guard let artwork = toggleArtwork(node) else { return measureGroup(node, proposal) }
        let control = artwork.controlSize
        guard !childNodes(node).isEmpty else { return control }
        let label = measureGroup(node, toggleLabelProposal(artwork, proposal))
        return LayoutSize(width: label.width + artwork.labelSpacing + control.width, height: max(label.height, control.height))
    }

    private func placeToggle(_ node: Node, in rect: LayoutRect, proposal: ProposedViewSize) {
        guard let artwork = toggleArtwork(node) else { return placeGroup(node, in: rect, proposal: proposal) }
        let children = childNodes(node)
        guard !children.isEmpty else { return }
        let labelProposal = toggleLabelProposal(artwork, proposal)
        let label = measureGroup(node, labelProposal)
        // the label's side: leading for the switch, trailing for the checkbox; flipped under right-to-left
        let labelOnLeft = artwork.labelLeads != mirrors(node)
        let labelRect = LayoutRect(x: labelOnLeft ? rect.minX : rect.maxX - label.width,
                                   y: rect.minY + (rect.height - label.height) / 2, width: label.width, height: label.height)
        if children.count == 1 {
            place(children[0], in: labelRect, proposal: labelProposal)
        } else {
            placeStack(children, groupStackSpec, in: labelRect, proposal: labelProposal, mirrored: mirrors(node))
        }
    }

    // MARK: Slider

    /// The control alone: as wide as it is offered (its ideal width, 30 pt, when nothing is proposed) and 16 pt high.
    private func measureSlider(_ proposal: ProposedViewSize) -> LayoutSize {
        // like SwiftUI's, a slider can take any width: an unbounded proposal (a stack asking how flexible it is) reports an unbounded width, so a stack gives it what its
        // siblings leave (macOS: HStack { Text; Slider; Text } gives the slider the rest)
        if let width = proposal.width, width == .infinity { return LayoutSize(width: .infinity, height: SliderSpec.height) }
        return LayoutSize(width: finiteLength(proposal.width) ?? SliderSpec.idealTrackWidth, height: SliderSpec.height)
    }

    private func placeSlider(_ node: Node, in rect: LayoutRect) {
        node.sliderTrack = snapToPixelGrid(LayoutRect(x: rect.minX, y: rect.minY + (rect.height - SliderSpec.height) / 2, width: rect.width, height: SliderSpec.height), scale: scale)
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
        let gaps = stackGaps(children, spec)
        let spacingTotal = gaps.reduce(0, +)
        let crossLimit = axis.crossLimit(proposal)
        let minLengths: [CGFloat?] = children.map { spacerLength($0, axis) }
        let fixed: [LayoutSize?] = children.map { fixedStackSize($0, axis, crossLimit) }
        var sizes = Array(repeating: LayoutSize.zero, count: children.count)
        var proposals = Array(repeating: ProposedViewSize.unspecified, count: children.count)

        if let limit = axis.mainLimit(proposal) {
            // Higher layout priorities are offered space first, each priority group keeping the minimum size of every lower group in reserve; within a group the
            // least flexible child goes first, so that flexible children (spacers) receive what remains.
            let available = max(0, limit - spacingTotal)
            var leastSizes = Array(repeating: CGFloat(0), count: children.count)
            let flex: [CGFloat] = children.indices.map { index in
                if minLengths[index] != nil { leastSizes[index] = minLengths[index] ?? 0; return CGFloat.infinity }
                let least = axis.main(measure(children[index], axis.proposal(main: 0, cross: crossLimit)))
                let most = axis.main(measure(children[index], axis.proposal(main: CGFloat.infinity, cross: crossLimit)))
                leastSizes[index] = least
                return most - least
            }
            let priorities = children.map { layoutPriority(of: $0) }
            var remaining = available
            for priority in Set(priorities).sorted(by: >) {
                let group = children.indices.filter { priorities[$0] == priority }.sorted { (flex[$0], $0) < (flex[$1], $1) }
                let spacers = group.filter { minLengths[$0] != nil }
                let others = group.filter { minLengths[$0] == nil }
                let reservedLower = children.indices.filter { priorities[$0] < priority }.reduce(CGFloat(0)) { $0 + leastSizes[$1] }
                // A Spacer keeps its minimum length in reserve and takes what the others leave (macOS: HStack { A; Spacer(); B } in 200 pt gives A and B 96 pt each).
                let reservedSpacers = spacers.reduce(CGFloat(0)) { $0 + leastSizes[$1] }
                var left = others.count
                for index in others {
                    let share = max(0, (remaining - reservedLower - reservedSpacers) / CGFloat(left))
                    let proposal = axis.proposal(main: share, cross: crossLimit)
                    let size = fixed[index] ?? measure(children[index], proposal)
                    sizes[index] = size
                    proposals[index] = proposal
                    remaining -= axis.main(size)
                    left -= 1
                }
                var spacersLeft = spacers.count
                for index in spacers {
                    let share = max(0, (remaining - reservedLower) / CGFloat(spacersLeft))
                    let proposal = axis.proposal(main: share, cross: crossLimit)
                    let measured = measure(children[index], proposal)
                    let size = axis.size(main: max(leastSizes[index], share), cross: axis.cross(measured))
                    sizes[index] = size
                    proposals[index] = proposal
                    remaining -= axis.main(size)
                    spacersLeft -= 1
                }
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

        var contentCross = sizes.map(axis.cross).max() ?? 0
        if spec.cross.isBaseline, axis == .horizontal, !children.isEmpty {
            let b = baselineOffsets(children, sizes, proposals, spec.cross)
            contentCross = b.extent
        }
        let cross = spec.fillsCross ? (crossLimit ?? contentCross) : contentCross
        let main = sizes.reduce(0) { $0 + axis.main($1) } + spacingTotal
        return StackPlan(children: children, sizes: sizes, proposals: proposals, size: axis.size(main: main, cross: cross), gaps: gaps)
    }

    // MARK: Baselines (round 5 block 33)

    /// Where each child of a horizontal stack sits, vertically, so that their first (or last) text baselines line up, and the height the row then needs. A child with no
    /// text counts its bottom edge as its baseline (SwiftUI: a view with no baseline aligns by its bottom edge).
    func baselineOffsets(_ children: [Node], _ sizes: [LayoutSize], _ proposals: [ProposedViewSize], _ alignment: CrossAlignment) -> (offsets: [CGFloat], extent: CGFloat) {
        var base: [CGFloat] = []
        for (index, child) in children.enumerated() {
            let found = baselines(of: child, proposals[index])
            base.append((alignment == .lastBaseline ? found?.last : found?.first) ?? sizes[index].height)
        }
        let top = base.max() ?? 0
        var extent: CGFloat = 0
        var offsets: [CGFloat] = []
        for (index, b) in base.enumerated() {
            offsets.append(top - b)
            extent = max(extent, top - b + sizes[index].height)
        }
        return (offsets, extent)
    }

    /// The first and last text baselines of a node laid out under `proposal`, from the node's top edge; nil when it has no text.
    func baselines(of node: Node, _ proposal: ProposedViewSize) -> (first: CGFloat, last: CGFloat)? {
        switch node.kind {
        case .text(let string):
            _ = measureText(node, node.environment.textCase?.apply(string) ?? string, width: proposal.width)
            return node.memoBase[finiteLength(proposal.width)]
        case .modifier(.padding(let insets)):
            guard let child = childNodes(node).first else { return nil }
            let inner = ProposedViewSize(width: proposal.width.map { max(0, $0 - insets.horizontal) }, height: proposal.height.map { max(0, $0 - insets.vertical) })
            return baselines(of: child, inner).map { ($0.first + insets.top, $0.last + insets.top) }
        case .modifier(.frame(let frame)):
            guard let child = childNodes(node).first else { return nil }
            let childProposal = ProposedViewSize(width: frame.width ?? proposal.width, height: frame.height ?? proposal.height)
            guard let inner = baselines(of: child, childProposal) else { return nil }
            let childSize = measure(child, childProposal)
            let y = alignmentOffset(frame.alignment.vertical, available: (frame.height ?? childSize.height) - childSize.height)
            return (inner.first + y, inner.last + y)
        case .modifier(.flexibleFrame(let frame)):
            guard let child = childNodes(node).first else { return nil }
            let childProposal = frame.childProposal(proposal)
            guard let inner = baselines(of: child, childProposal) else { return nil }
            let childSize = measure(child, childProposal)
            let y = alignmentOffset(frame.alignment.vertical, available: frame.frameSize(for: childSize, proposal: proposal).height - childSize.height)
            return (inner.first + y, inner.last + y)
        case .modifier(.fixedSize(let horizontal, let vertical)):
            guard let child = childNodes(node).first else { return nil }
            let childProposal = fixedProposal(proposal, horizontal, vertical)
            guard let inner = baselines(of: child, childProposal) else { return nil }
            // the child is centred in the frame this view is given; the baseline is the child's own from its top edge
            return inner
        case .stack(let spec) where spec.name == "List":
            return nil
        case .stack(let spec):
            let children = childNodes(node)
            guard !children.isEmpty else { return nil }
            switch spec.axis {
            case .overlap, .overlay:
                return baselines(of: children[0], proposal)
            case .vertical:
                let plan = stackPlan(children, spec, proposal)
                var y: CGFloat = 0
                var first: CGFloat?, last: CGFloat?
                for (index, child) in children.enumerated() {
                    if let b = baselines(of: child, plan.proposals[index]) {
                        if first == nil { first = y + b.first }
                        last = y + b.last
                    }
                    y += plan.sizes[index].height + (index < plan.gaps.count ? plan.gaps[index] : 0)
                }
                guard let first, let last else { return nil }
                return (first, last)
            case .horizontal:
                let plan = stackPlan(children, spec, proposal)
                let rowHeight = plan.size.height
                let aligned = spec.cross.isBaseline ? baselineOffsets(children, plan.sizes, plan.proposals, spec.cross).offsets : nil
                var first: CGFloat?, last: CGFloat?
                for (index, child) in children.enumerated() {
                    guard let b = baselines(of: child, plan.proposals[index]) else { continue }
                    let slack = rowHeight - plan.sizes[index].height
                    let y: CGFloat
                    switch spec.cross {
                    case .start: y = 0
                    case .middle: y = slack / 2
                    case .end: y = slack
                    case .firstBaseline, .lastBaseline: y = aligned?[index] ?? 0
                    }
                    first = min(first ?? .infinity, y + b.first)
                    last = max(last ?? -.infinity, y + b.last)
                }
                guard let first, let last else { return nil }
                return (first, last)
            }
        case .user, .modifier, .menu:
            let children = childNodes(node)
            return children.count == 1 ? baselines(of: children[0], proposal) : nil
        default:
            return nil
        }
    }

    /// The `.layoutPriority(_:)` a stack reads for this child: the first one found down the chain of wrappers that pass a single child through (a modifier or a
    /// user view around the view that sets it). 0 when none.
    func layoutPriority(of node: Node) -> Double {
        var current = node
        while true {
            if case .modifier(.layoutPriority(let value)) = current.kind { return value }
            // `padding` and the frame modifiers do not forward a priority set beneath them (macOS: `.layoutPriority(1).padding(4)` and `.layoutPriority(1).frame(maxWidth: .infinity)`
            // behave as no priority); user views and the other modifiers (opacity, onAppear, ...) do.
            switch current.kind {
            case .modifier(.padding), .modifier(.frame), .modifier(.flexibleFrame): return 0
            default: break
            }
            guard current.kind.passesThrough else { return 0 }
            let children = childNodes(current)
            guard children.count == 1 else { return 0 }
            current = children[0]
        }
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
        let baseline = spec.cross.isBaseline && axis == .horizontal ? baselineOffsets(children, plan.sizes, plan.proposals, spec.cross) : nil
        var offset = axis == .vertical ? rect.minY : rect.minX
        for (index, child) in children.enumerated() {
            var size = plan.sizes[index]
            // A Divider directly in a stack fills the stack's cross axis (the tallest sibling of an HStack, the widest of a VStack), not just the proposal it was measured under.
            if case .divider = child.kind { size = axis.size(main: axis.main(size), cross: crossLength) }
            let slack = crossLength - axis.cross(size)
            let crossOffset: CGFloat
            switch spec.cross {
            case .start: crossOffset = 0
            case .middle: crossOffset = slack / 2
            case .end: crossOffset = slack
            case .firstBaseline, .lastBaseline: crossOffset = axis == .horizontal ? (baseline?.offsets[index] ?? 0) : slack / 2
            }
            let origin = axis == .vertical
                ? LayoutPoint(x: rect.minX + crossOffset, y: offset)
                : LayoutPoint(x: offset, y: rect.minY + crossOffset)
            place(child, in: mirroredRect(LayoutRect(origin: origin, size: size), in: rect, if: mirrored), proposal: plan.proposals[index])
            offset += axis.main(size) + (index < plan.gaps.count ? plan.gaps[index] : 0)
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
            case .center, .firstTextBaseline, .lastTextBaseline: y = rect.minY + ySlack / 2
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
            case .center, .firstTextBaseline, .lastTextBaseline: y = rect.minY + ySlack / 2
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

    /// The distance between each child and the next. A default (nil) spacing is 0 next to a Spacer.
    func stackGaps(_ children: [Node], _ spec: StackSpec) -> [CGFloat] {
        guard children.count > 1 else { return [] }
        return (0..<(children.count - 1)).map { index in
            spec.spacingIsDefault && (isSpacerView(children[index]) || isSpacerView(children[index + 1])) ? 0 : spec.spacing
        }
    }

    /// A Spacer, or a Spacer seen through single-child wrappers (`Spacer().frame(width: 30)`).
    private func isSpacerView(_ node: Node) -> Bool {
        if case .spacer = node.kind { return true }
        switch node.kind {
        case .modifier(.frame), .modifier(.flexibleFrame): break
        default: guard node.kind.passesThrough else { return false }
        }
        let children = childNodes(node)
        return children.count == 1 && isSpacerView(children[0])
    }

    /// True when the nearest enclosing stack lays out horizontally (HStack): the Divider is then a vertical rule. ZStack, overlays and everything else give a horizontal rule.
    func dividerIsVertical(_ node: Node) -> Bool {
        var child = node
        while let parent = child.parent {
            if case .stack(let spec) = parent.kind {
                // The base of an `.overlay` modifier belongs to the stack around the modified view; the overlaid view does not (it sits in a ZStack-like layer: a horizontal rule).
                if spec.axis == .overlay, childNodes(parent).first === child { child = parent; continue }
                return spec.axis == .horizontal
            }
            child = parent
        }
        return false
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
        case .center, .firstTextBaseline, .lastTextBaseline: return available / 2
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

    /// A TextField takes the width it is offered (else its text plus the bezel inset) and a fixed height: 24 pt bezeled, one text line plain
    /// (macOS 27 measured: `AppKitTextField` fills the proposal; ideal width = text + 2 x 4 pt, the placeholder when empty).
    private func measureTextField(_ node: Node, _ proposal: ProposedViewSize) -> LayoutSize {
        let artwork = TextFieldMetrics.artwork(forStyle: node.environment.textFieldStyleMetadata)
        let shown = node.textInput?.display ?? ""
        let text = shown.isEmpty ? (placeholderOf(node) ?? "") : shown
        let measured = measureText(node, text, width: nil)
        let inset = TextFieldMetrics.textInset(artwork)
        let height = artwork == .bezel ? TextFieldMetrics.bezelHeight : max(measured.height, TextFieldMetrics.plainHeight)
        return LayoutSize(width: finiteLength(proposal.width) ?? measured.width + 2 * inset, height: height)
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
            node.memoBase.removeAll()
        }
        if let cached = node.memo[wrapWidth] { return cached }
        let request = TextMeasureRequest(
            text: string, fontID: font.id, proposedWidth: wrapWidth, scale: scale,
            fontMetadata: font.metadata, lineLimit: lineLimit
        )
        let measured = measurer.measure(request)
        // A Text never reports more width than it was offered (macOS 27 measured, decision L1): offered 0 it reports 0, so in a stack its flexibility range runs
        // from 0 to its one-line width and a lower layout priority gives way to a higher one. A measurer that reads a zero bound as no bound (the renderer) is corrected here.
        let size = wrapWidth.map { LayoutSize(width: min(measured.size.width, max(0, $0)), height: measured.size.height) } ?? measured.size
        node.memo[wrapWidth] = size
        // the first line's baseline, and the last line's (lines are as tall as the line height: the measured height over the line count)
        let lineHeight = measured.lineCount > 0 ? measured.size.height / CGFloat(measured.lineCount) : 0
        // a measurer that reports its own last baseline (the renderer stacks by the Mac pitch, not height / lineCount) wins
        node.memoBase[wrapWidth] = (measured.baseline, measured.lastBaseline ?? (measured.baseline + CGFloat(max(0, measured.lineCount - 1)) * lineHeight))
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


extension CrossAlignment {
    var isBaseline: Bool { self == .firstBaseline || self == .lastBaseline }
}
