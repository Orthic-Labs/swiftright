import Foundation

// Issue #68 (MarkdownUI on SwiftRight): Grid, GridRow and gridColumnAlignment.
//
// SwiftUI semantics implemented:
//   - every GridRow's cells line up in columns: a column is as wide as its widest cell, a row as tall as its tallest cell;
//   - column widths are negotiated like HStack children: the least flexible column is offered its share first, so wrapping text takes what it needs and a flexible cell
//     (Color, frame(maxWidth: .infinity)) takes what is left; without a width proposal each column is as wide as its widest ideal cell;
//   - row heights likewise (a finite height proposal is shared, rows of text keep their own height);
//   - a cell is proposed its column width and row height and sits in that area by the column's horizontal alignment (the grid's `alignment.horizontal`, or the
//     `gridColumnAlignment` of the first cell of the column that sets one) and the row's vertical alignment (`GridRow(alignment:)`, else the grid's `alignment.vertical`);
//     `.firstTextBaseline`, `.lastTextBaseline` and custom vertical alignments align the row's cells on the guide;
//   - a direct child of the Grid that is not a GridRow (a Divider, a Text) spans the grid's width; a Divider takes no part in sizing.
// Not implemented: gridCellColumns, gridCellAnchor, gridCellUnsizedAxes, right-to-left mirroring, custom horizontal alignments as column guides (they centre).

@MainActor protocol GridContainer {}

@MainActor protocol GridRowMarker {
    var rowAlignment: VerticalAlignment? { get }
}

/// What the grid computed for one row, handed to the row's own layout: absolute frames of its cells.
struct GridRowPlan {
    var cells: [(rect: LayoutRect, proposal: ProposedViewSize)] = []
}

/// Apple: https://developer.apple.com/documentation/swiftui/grid
public struct Grid<Content: View>: View, PrimitiveView, GridContainer {
    let alignment: Alignment
    let horizontalSpacing: CGFloat?
    let verticalSpacing: CGFloat?
    let content: Content

    /// A nil spacing is the default, 8 points.
    /// Apple: https://developer.apple.com/documentation/swiftui/grid/init(alignment:horizontalspacing:verticalspacing:content:)
    public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind {
        LayoutRoot(layout: GridLayout(alignment: alignment, horizontalSpacing: horizontalSpacing ?? defaultStackSpacing,
                                      verticalSpacing: verticalSpacing ?? defaultStackSpacing), content: content).nodeKind
    }
    var nodeContent: (any View)? { content }
}

/// Apple: https://developer.apple.com/documentation/swiftui/gridrow
public struct GridRow<Content: View>: View, PrimitiveView, GridRowMarker {
    let alignment: VerticalAlignment?
    let content: Content

    /// Apple: https://developer.apple.com/documentation/swiftui/gridrow/init(alignment:content:)
    public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var rowAlignment: VerticalAlignment? { alignment }
    var nodeKind: NodeKind { LayoutRoot(layout: GridRowLayout(), content: content).nodeKind }
    var nodeContent: (any View)? { content }
}

/// `.gridColumnAlignment` data: read by the Grid from a cell.
struct GridCellSpec {
    var columnAlignment: HorizontalAlignment?
}

extension View {
    /// Aligns every cell of this cell's column horizontally by `guide`, overriding the grid's alignment; when several cells of a column set one, the topmost wins.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/gridcolumnalignment(_:)
    public func gridColumnAlignment(_ guide: HorizontalAlignment) -> some View {
        Modified(content: self, spec: .gridCell(GridCellSpec(columnAlignment: guide)))
    }
}

/// A GridRow outside a Grid (or one the grid has not planned): its cells run left to right at their ideal sizes, 8 points apart, as an HStack would.
@MainActor
struct GridRowLayout: Layout {
    typealias Cache = GridRowPlan

    func makeCache(subviews: Subviews) -> GridRowPlan { GridRowPlan() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout GridRowPlan) -> LayoutSize {
        var width: CGFloat = 0, height: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size: LayoutSize = subview.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height))
            width += size.width + (index > 0 ? defaultStackSpacing : 0)
            height = max(height, size.height)
        }
        return LayoutSize(width: width, height: height)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout GridRowPlan) {
        if cache.cells.count == subviews.count {
            for (index, subview) in subviews.enumerated() {
                subview.graph.place(subview.node, in: cache.cells[index].rect, proposal: cache.cells[index].proposal)
            }
            return
        }
        var x = bounds.minX
        for subview in subviews {
            let size: LayoutSize = subview.sizeThatFits(ProposedViewSize(width: nil, height: bounds.height))
            subview.graph.place(subview.node, in: LayoutRect(x: x, y: bounds.minY + (bounds.height - size.height) / 2, width: size.width, height: size.height),
                                proposal: ProposedViewSize(width: nil, height: bounds.height))
            x += size.width + defaultStackSpacing
        }
    }
}

@MainActor
struct GridLayout: Layout {
    typealias Cache = Void

    let alignment: Alignment
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    private struct Row {
        let node: Node
        let cells: [Node]
        let alignment: VerticalAlignment
    }

    private enum Item {
        case row(Row)
        case full(Node)
    }

    private struct PlannedCell {
        var rect: LayoutRect
        var proposal: ProposedViewSize
    }

    private struct PlannedItem {
        let node: Node
        var rect: LayoutRect
        var proposal: ProposedViewSize
        var cells: [PlannedCell]
        var isRow: Bool
    }

    private struct Plan {
        var size: LayoutSize
        var items: [PlannedItem]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> LayoutSize {
        plan(subviews, proposal).size
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard let graph = subviews.first?.graph else { return }
        let planned = plan(subviews, proposal)
        for item in planned.items {
            let rect = LayoutRect(x: bounds.minX + item.rect.minX, y: bounds.minY + item.rect.minY, width: item.rect.width, height: item.rect.height)
            if item.isRow {
                var rowPlan = GridRowPlan()
                for cell in item.cells {
                    rowPlan.cells.append((LayoutRect(x: bounds.minX + cell.rect.minX, y: bounds.minY + cell.rect.minY,
                                                     width: cell.rect.width, height: cell.rect.height), cell.proposal))
                }
                item.node.layoutStorage = rowPlan
            }
            graph.place(item.node, in: rect, proposal: item.proposal)
        }
    }

    // MARK: Planning

    private func areaGuide(_ alignment: HorizontalAlignment, _ length: CGFloat) -> CGFloat {
        switch alignment.kind {
        case .leading: return 0
        case .trailing: return length
        case .center, .custom: return length / 2
        }
    }

    private func areaGuide(_ alignment: VerticalAlignment, _ length: CGFloat) -> CGFloat {
        switch alignment.kind {
        case .top: return 0
        case .bottom: return length
        default: return length / 2
        }
    }

    private func isDivider(_ node: Node, _ graph: Graph) -> Bool {
        var current = node
        while true {
            if case .divider = current.kind { return true }
            guard current.kind.passesThrough else { return false }
            let children = graph.childNodes(current)
            guard children.count == 1 else { return false }
            current = children[0]
        }
    }

    private func columnAlignment(of node: Node, _ graph: Graph) -> HorizontalAlignment? {
        var current = node
        while true {
            if case .modifier(.gridCell(let spec)) = current.kind, let alignment = spec.columnAlignment { return alignment }
            guard current.kind.passesThrough else { return nil }
            let children = graph.childNodes(current)
            guard children.count == 1 else { return nil }
            current = children[0]
        }
    }

    /// The least flexible column is offered its share of what remains first (as an HStack does); `flex` orders them.
    private func distribute(_ count: Int, limit: CGFloat, flex: [CGFloat], size: (Int, CGFloat) -> CGFloat) -> [CGFloat] {
        var result = [CGFloat](repeating: 0, count: count)
        var remaining = max(0, limit)
        var left = count
        for index in (0..<count).sorted(by: { (flex[$0], $0) < (flex[$1], $1) }) {
            let share = max(0, remaining / CGFloat(left))
            let length = size(index, share)
            result[index] = length
            remaining -= length
            left -= 1
        }
        return result
    }

    private func plan(_ subviews: Subviews, _ proposal: ProposedViewSize) -> Plan {
        guard let graph = subviews.first?.graph else { return Plan(size: .zero, items: []) }
        var items: [Item] = []
        for subview in subviews {
            if let marker = subview.node.view as? any GridRowMarker {
                items.append(.row(Row(node: subview.node, cells: graph.childNodes(subview.node), alignment: marker.rowAlignment ?? alignment.vertical)))
            } else {
                items.append(.full(subview.node))
            }
        }
        let rows: [Row] = items.compactMap { if case .row(let row) = $0 { return row } else { return nil } }
        let columnCount = rows.map { $0.cells.count }.max() ?? 0
        let columnCells: [[Node]] = (0..<columnCount).map { column in rows.compactMap { column < $0.cells.count ? $0.cells[column] : nil } }

        // Column widths.
        func width(_ node: Node, _ proposed: CGFloat?) -> CGFloat {
            graph.measure(node, ProposedViewSize(width: proposed, height: nil)).width
        }
        let spacingTotal = horizontalSpacing * CGFloat(max(0, columnCount - 1))
        var columnWidths = [CGFloat](repeating: 0, count: columnCount)
        if let limit = finiteLength(proposal.width) {
            let flex: [CGFloat] = columnCells.map { cells in
                let least = cells.map { width($0, 0) }.max() ?? 0
                let most = cells.map { width($0, .infinity) }.max() ?? 0
                return most - least
            }
            columnWidths = distribute(columnCount, limit: limit - spacingTotal, flex: flex) { column, share in
                columnCells[column].map { width($0, share) }.max() ?? 0
            }
        } else {
            for column in 0..<columnCount { columnWidths[column] = columnCells[column].map { width($0, nil) }.max() ?? 0 }
        }
        var columnX = [CGFloat](repeating: 0, count: columnCount)
        var x: CGFloat = 0
        for column in 0..<columnCount {
            columnX[column] = x
            x += columnWidths[column] + horizontalSpacing
        }
        var totalWidth = columnWidths.reduce(0, +) + spacingTotal
        for case .full(let node) in items where !isDivider(node, graph) {
            totalWidth = max(totalWidth, graph.measure(node, ProposedViewSize(width: finiteLength(proposal.width), height: nil)).width)
        }

        // Column alignments: the first cell of a column that sets one.
        var columnAlignments = [HorizontalAlignment](repeating: alignment.horizontal, count: columnCount)
        for column in 0..<columnCount {
            if let set = columnCells[column].lazy.compactMap({ columnAlignment(of: $0, graph) }).first { columnAlignments[column] = set }
        }

        // Row heights.
        func isGuideRow(_ row: Row) -> Bool {
            switch row.alignment.kind {
            case .top, .center, .bottom: return false
            default: return true
            }
        }
        func cellSizes(_ row: Row, share: CGFloat?) -> [(size: LayoutSize, proposal: ProposedViewSize)] {
            row.cells.enumerated().map { column, cell in
                let proposed = ProposedViewSize(width: columnWidths[column], height: share)
                return (graph.measure(cell, proposed), proposed)
            }
        }
        func itemHeight(_ item: Item, share: CGFloat?) -> CGFloat {
            switch item {
            case .full(let node):
                return graph.measure(node, ProposedViewSize(width: totalWidth, height: share)).height
            case .row(let row):
                let cells = cellSizes(row, share: share)
                guard isGuideRow(row) else { return cells.map { $0.size.height }.max() ?? 0 }
                let guides = zip(row.cells, cells).map { graph.guideValue(.v(row.alignment), of: $0, size: $1.size, proposal: $1.proposal) }
                let line = guides.max() ?? 0
                return zip(guides, cells).map { line - $0 + $1.size.height }.max() ?? 0
            }
        }
        let verticalSpacingTotal = verticalSpacing * CGFloat(max(0, items.count - 1))
        var heights = [CGFloat](repeating: 0, count: items.count)
        if let limit = finiteLength(proposal.height), !items.isEmpty {
            let flex: [CGFloat] = items.map { itemHeight($0, share: .infinity) - itemHeight($0, share: 0) }
            heights = distribute(items.count, limit: limit - verticalSpacingTotal, flex: flex) { index, share in itemHeight(items[index], share: share) }
        } else {
            for (index, item) in items.enumerated() { heights[index] = itemHeight(item, share: nil) }
        }

        // Frames, relative to the grid's origin.
        var planned: [PlannedItem] = []
        var y: CGFloat = 0
        for (index, item) in items.enumerated() {
            let height = heights[index]
            switch item {
            case .full(let node):
                let proposed = ProposedViewSize(width: totalWidth, height: height)
                let size = graph.measure(node, proposed)
                let guide = graph.guideValue(.h(alignment.horizontal), of: node, size: size, proposal: proposed)
                let rect = LayoutRect(x: areaGuide(alignment.horizontal, totalWidth) - guide, y: y, width: size.width, height: size.height)
                planned.append(PlannedItem(node: node, rect: rect, proposal: proposed, cells: [], isRow: false))
            case .row(let row):
                var cells: [PlannedCell] = []
                let proposals = row.cells.indices.map { ProposedViewSize(width: columnWidths[$0], height: height) }
                let sizes = row.cells.indices.map { graph.measure(row.cells[$0], proposals[$0]) }
                var lineGuides: [CGFloat] = []
                var line: CGFloat = 0
                if isGuideRow(row) {
                    lineGuides = row.cells.indices.map { graph.guideValue(.v(row.alignment), of: row.cells[$0], size: sizes[$0], proposal: proposals[$0]) }
                    line = lineGuides.max() ?? 0
                }
                for column in row.cells.indices {
                    let cell = row.cells[column]
                    let size = sizes[column]
                    let horizontal = columnAlignments[column]
                    let cellX = columnX[column] + areaGuide(horizontal, columnWidths[column])
                        - graph.guideValue(.h(horizontal), of: cell, size: size, proposal: proposals[column])
                    let cellY: CGFloat
                    if isGuideRow(row) {
                        cellY = y + line - lineGuides[column]
                    } else {
                        cellY = y + areaGuide(row.alignment, height) - graph.guideValue(.v(row.alignment), of: cell, size: size, proposal: proposals[column])
                    }
                    cells.append(PlannedCell(rect: LayoutRect(x: cellX, y: cellY, width: size.width, height: size.height), proposal: proposals[column]))
                }
                planned.append(PlannedItem(node: row.node, rect: LayoutRect(x: 0, y: y, width: totalWidth, height: height),
                                           proposal: ProposedViewSize(width: totalWidth, height: height), cells: cells, isRow: true))
            }
            y += height + verticalSpacing
        }
        let totalHeight = items.isEmpty ? 0 : y - verticalSpacing
        return Plan(size: LayoutSize(width: totalWidth, height: totalHeight), items: planned)
    }
}
