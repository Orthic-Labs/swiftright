import Foundation

// Issue #82 (SR2 S2): LazyVGrid and GridItem.
//
// The track algorithm is the one measured on macOS 27 (offscreen NSHostingView frames, 22 Oct 2026; fixed, flexible with limits and adaptive items, default and explicit spacing):
//   - a GridItem is a column track; spacing between tracks is the spacing of the track on the left (default 8), and `LazyVGrid(spacing:)` is the row spacing (default 8);
//   - `.fixed(s)` takes s; `.flexible(minimum:maximum:)` (default minimum 10) and `.adaptive(minimum:maximum:)` share what is left equally, clamped to their range;
//   - an adaptive track of width T holds n = max(1, floor((T + s) / (minimum + s))) columns of width (T - (n - 1) s) / n (at most `maximum`);
//   - a grid narrower than its container is placed by the grid's horizontal alignment (centre by default), a wider one overflows about the same point;
//   - a cell is proposed its column width and its own height, and sits in the column by the item's alignment (centre by default).
// The cells are all realized (no virtualization, as LazyVStack): laziness is not visible in a layout.

/// Apple: https://developer.apple.com/documentation/swiftui/griditem
public struct GridItem: Sendable {
    /// Apple: https://developer.apple.com/documentation/swiftui/griditem/size-swift.enum
    public enum Size: Sendable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }

    public var size: Size
    public var spacing: CGFloat?
    public var alignment: Alignment?

    public init(_ size: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/pinnedscrollableviews
public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 2)
}

/// Apple: https://developer.apple.com/documentation/swiftui/lazyvgrid
public struct LazyVGrid<Content: View>: View, PrimitiveView {
    let columns: [GridItem]
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content

    /// `pinnedViews` is accepted and ignored (sections are not modelled).
    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(),
                @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind {
        LayoutRoot(layout: LazyVGridLayout(columns: columns, alignment: alignment, rowSpacing: spacing ?? 8), content: content).nodeKind
    }
    var nodeContent: (any View)? { content }
}

/// The columns of a grid for a container width: x offset of each column from the grid's left edge and its width.
struct GridColumns: Equatable {
    var columns: [(x: CGFloat, width: CGFloat, alignment: Alignment?)] = []
    var width: CGFloat = 0

    static func == (a: GridColumns, b: GridColumns) -> Bool {
        a.width == b.width && a.columns.count == b.columns.count && zip(a.columns, b.columns).allSatisfy { $0.x == $1.x && $0.width == $1.width }
    }

    /// `available` nil: no width proposal, each track takes its ideal width (fixed size, otherwise its minimum).
    static func compute(_ items: [GridItem], available: CGFloat?) -> GridColumns {
        let defaultSpacing: CGFloat = 8
        guard !items.isEmpty else { return GridColumns() }
        // each track's range
        struct Track { var lo: CGFloat; var hi: CGFloat; var fixed: Bool; var adaptive: Bool; var itemMax: CGFloat; var itemMin: CGFloat }
        var tracks: [Track] = items.map { item in
            switch item.size {
            case .fixed(let s): return Track(lo: s, hi: s, fixed: true, adaptive: false, itemMax: s, itemMin: s)
            case .flexible(let lo, let hi): return Track(lo: lo, hi: max(lo, hi), fixed: false, adaptive: false, itemMax: hi, itemMin: lo)
            case .adaptive(let lo, let hi): return Track(lo: lo, hi: .infinity, fixed: false, adaptive: true, itemMax: hi, itemMin: lo)
            }
        }
        let gaps = items.dropLast().map { $0.spacing ?? defaultSpacing }
        var widths = tracks.map { $0.lo }
        if let available {
            var remaining = available - gaps.reduce(0, +)
            var open: [Int] = []
            for (i, t) in tracks.enumerated() { if t.fixed { widths[i] = t.lo; remaining -= t.lo } else { open.append(i) } }
            // share equally, clamped to each track's range: tracks that cannot take the share are fixed at their limit and the rest share what is left
            while !open.isEmpty {
                let share = remaining / CGFloat(open.count)
                if let i = open.first(where: { tracks[$0].lo > share }) {
                    widths[i] = tracks[i].lo; remaining -= tracks[i].lo; open.removeAll { $0 == i }; continue
                }
                if let i = open.first(where: { tracks[$0].hi < share }) {
                    widths[i] = tracks[i].hi; remaining -= tracks[i].hi; open.removeAll { $0 == i }; continue
                }
                for i in open { widths[i] = share }
                break
            }
        }
        tracks = tracks.map { $0 }
        var out = GridColumns()
        var x: CGFloat = 0
        for (i, item) in items.enumerated() {
            let t = tracks[i], trackW = widths[i]
            let s = item.spacing ?? defaultSpacing
            if t.adaptive {
                let n = max(1, Int(((trackW + s) / (t.itemMin + s)).rounded(.down)))
                var w = (trackW - CGFloat(n - 1) * s) / CGFloat(n)
                if w > t.itemMax { w = t.itemMax }
                for k in 0..<n { out.columns.append((x: x + CGFloat(k) * (w + s), width: w, alignment: item.alignment)) }
                x += CGFloat(n) * w + CGFloat(n - 1) * s
            } else {
                out.columns.append((x: x, width: trackW, alignment: item.alignment))
                x += trackW
            }
            if i < gaps.count { x += gaps[i] }
        }
        out.width = x
        return out
    }
}

struct LazyVGridLayout: Layout {
    let columns: [GridItem]
    let alignment: HorizontalAlignment
    let rowSpacing: CGFloat

    private func plan(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (cols: GridColumns, rowHeights: [CGFloat]) {
        let w = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let cols = GridColumns.compute(columns, available: w)
        guard !cols.columns.isEmpty else { return (cols, []) }
        var rows: [CGFloat] = []
        for (i, sub) in subviews.enumerated() {
            let c = i % cols.columns.count, r = i / cols.columns.count
            let h = sub.sizeThatFits(ProposedViewSize(width: cols.columns[c].width, height: nil)).height
            if r == rows.count { rows.append(h) } else { rows[r] = max(rows[r], h) }
        }
        return (cols, rows)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> LayoutSize {
        let p = plan(proposal, subviews)
        let height = p.rowHeights.reduce(0, +) + CGFloat(max(0, p.rowHeights.count - 1)) * rowSpacing
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? p.cols.width
        return LayoutSize(width: width, height: height)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let p = plan(ProposedViewSize(width: bounds.size.width, height: proposal.height), subviews)
        guard !p.cols.columns.isEmpty else { return }
        let free = bounds.size.width - p.cols.width
        let offset: CGFloat
        switch alignment.kind {
        case .leading: offset = 0
        case .trailing: offset = free
        default: offset = free / 2
        }
        var y = bounds.origin.y
        for (r, rowH) in p.rowHeights.enumerated() {
            for c in 0..<p.cols.columns.count {
                let i = r * p.cols.columns.count + c
                guard i < subviews.count else { break }
                let col = p.cols.columns[c]
                let proposalForCell = ProposedViewSize(width: col.width, height: nil)
                let size = subviews[i].sizeThatFits(proposalForCell)
                let a = col.alignment ?? .center
                let fx: CGFloat = { switch a.horizontal.kind { case .leading: return 0; case .trailing: return 1; default: return 0.5 } }()
                let fy: CGFloat = { switch a.vertical.kind { case .top: return 0; case .bottom: return 1; default: return 0.5 } }()
                let x = bounds.origin.x + offset + col.x + (col.width - size.width) * fx
                subviews[i].place(at: LayoutPoint(x: x, y: y + (rowH - size.height) * fy), proposal: proposalForCell)
            }
            y += rowH + rowSpacing
        }
    }
}
