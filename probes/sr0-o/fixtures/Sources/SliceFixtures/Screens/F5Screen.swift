import Foundation
import Observation
#if os(macOS)
import SwiftUI
#endif

/// Width-dependent custom layout. Subset per SR0 contract: sizeThatFits and placeSubviews only.
/// Placement, containment and mode are recorded in-process; paint and hit-test agreement is out-of-process.
struct WidthDependentLayout: Layout {
    let log: EventLog
    static let wideThreshold: CGFloat = 560
    static let gutter: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 480
        let frames = Self.plan(width: width, subviews: subviews, origin: .zero)
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let frames = Self.plan(width: bounds.width, subviews: subviews, origin: bounds.origin)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: frames[index].origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(frames[index].size)
            )
        }
        let wide = bounds.width >= Self.wideThreshold
        // A frame is contained when its edges lie inside the bounds (half-point tolerance for rounding).
        let outside = frames.filter { !Self.isContained($0, in: bounds) }
        let contained = outside.isEmpty
        let signature = "\(wide)|" + frames.map { "\($0)" }.joined(separator: ";")
        log.emitIfChanged("state", node: "layout", signature: signature, payload: [
            "mode": wide ? "wide" : "narrow",
            "width": Int(bounds.width),
            "contained": contained,
            "degenerate": bounds.width <= 0,
            "items": frames.count,
            "bounds": Self.describe(bounds),
            "outside": outside.map(Self.describe),
        ])
    }

    static func isContained(_ frame: CGRect, in bounds: CGRect) -> Bool {
        let tolerance: CGFloat = 0.5
        return frame.minX >= bounds.minX - tolerance && frame.maxX <= bounds.maxX + tolerance
            && frame.minY >= bounds.minY - tolerance && frame.maxY <= bounds.maxY + tolerance
    }

    static func describe(_ rect: CGRect) -> String {
        "x=\(rect.minX),y=\(rect.minY),w=\(rect.width),h=\(rect.height)"
    }

    static func plan(width: CGFloat, subviews: Subviews, origin: CGPoint) -> [CGRect] {
        let columns = width >= wideThreshold ? 2 : 1
        let columnWidth = (width - gutter * CGFloat(columns - 1)) / CGFloat(columns)
        var frames: [CGRect] = []
        var y = origin.y
        var rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let column = index % columns
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let x = origin.x + CGFloat(column) * (columnWidth + gutter)
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            if column == columns - 1 {
                y += rowHeight + gutter
                rowHeight = 0
            }
        }
        return frames
    }
}

// F5: width-dependent layout with async row update and insert while the window is resized.
struct F5Screen: View {
    @Bindable var model: RowModel

    var body: some View {
        FixtureScaffold(model: model) { focus in
            WidthDependentLayout(log: model.log) {
                ForEach($model.rows, id: \.id) { row in
                    EditableRowView(row: row, model: model, focus: focus)
                }
            }
        }
        .task { await model.runInsertAbove(key: "insert-1", slot: 98) }
        .task { await model.runRowUpdate(key: "update-1", slot: 1) }
    }
}
