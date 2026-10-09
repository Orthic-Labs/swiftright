import Foundation
import Observation
#if WORKLOAD_RUNTIME
import SwiftRightRuntime
typealias WSize = LayoutSize
typealias WRect = LayoutRect
typealias WPoint = LayoutPoint
#else
import SwiftUI
typealias WSize = CGSize
typealias WRect = CGRect
typealias WPoint = CGPoint
#endif

// SR0 workload screen. One source for the Mac (real SwiftUI) and Windows (SwiftRightRuntime) hosts.
// Only API in the SR0 slice inventory (CONTRACT section 2) is used: Text, TextField, VStack, HStack, ScrollView,
// ForEach over Binding<[Row]>, custom Layout, @Bindable, @FocusState, .task, .onAppear/.onDisappear, .padding,
// withAnimation (in the model). The two `#if` blocks below are host glue, not screen content.

/// Width-dependent two-column wrap layout: one column below 560 pt, two at or above it. Row heights depend on the
/// column width through each row's wrapped detail text.
struct WorkloadLayout: Layout {
    static let wideThreshold: CGFloat = 560
    static let gutter: CGFloat = 8

    struct Frame { var x: CGFloat; var y: CGFloat; var w: CGFloat; var h: CGFloat }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> WSize {
        let width = proposal.width ?? 480
        let frames = Self.plan(width: width, subviews: subviews)
        let height = frames.map { $0.y + $0.h }.max() ?? 0
        return WSize(width: width, height: height)
    }

    func placeSubviews(in bounds: WRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let frames = Self.plan(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let f = frames[index]
            subview.place(
                at: WPoint(x: bounds.minX + f.x, y: bounds.minY + f.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(WSize(width: f.w, height: f.h))
            )
        }
    }

    static func plan(width: CGFloat, subviews: Subviews) -> [Frame] {
        let columns = width >= wideThreshold ? 2 : 1
        let columnWidth = (width - gutter * CGFloat(columns - 1)) / CGFloat(columns)
        var frames: [Frame] = []
        frames.reserveCapacity(subviews.count)
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let column = index % columns
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            frames.append(Frame(x: CGFloat(column) * (columnWidth + gutter), y: y, w: columnWidth, h: size.height))
            rowHeight = max(rowHeight, size.height)
            if column == columns - 1 {
                y += rowHeight + gutter
                rowHeight = 0
            }
        }
        return frames
    }
}

/// One editable list row: slot label, text field, wrapped detail text, a per-row task (cancelled on removal).
struct WorkloadRowCell: View {
    let row: Binding<Row>
    let model: WorkloadModel
    let focus: FocusState<UUID?>.Binding

    var body: some View {
        let id = row.wrappedValue.id
        let slot = row.wrappedValue.slot
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(slot)")
                TextField("Row", text: Binding(get: { row.wrappedValue.text }, set: { model.userEdit(id, $0) }))
                    .focused(focus, equals: id)
            }
            Text(row.wrappedValue.detail)
        }
        .task { await model.rowTaskBody(id) }
        .onAppear { model.noteRowAppear() }
        .onDisappear { model.noteRowDisappear() }
    }
}

/// The workload root. Header: the visible-response counter ("typed N", the endpoint region), the pinned active
/// editor (typing target), a status line; then the scrolling 199-row content. Each piece reads the model state it shows in
/// its own body, so a keystroke (typed count, active text) re-evaluates the counter and the editor only, and the 199 rows
/// are re-evaluated only when `rows` changes (the same isolation the Mac host uses for `scrollPhase`).
public struct WorkloadRoot: View {
    @Bindable var model: WorkloadModel
    @FocusState private var focus: UUID?

    public init(model: WorkloadModel) {
        self._model = Bindable(wrappedValue: model)
    }

    public var body: some View {
        let _ = registerFocus($focus)
        VStack(alignment: .leading, spacing: 8) {
            TypedCounter(model: model)
            ActiveEditor(model: model, focus: $focus)
            StatusLine(model: model)
            WorkloadRowList(model: model, focus: $focus)
        }
        .padding(.all, 12)
    }

    @MainActor
    private func registerFocus(_ binding: FocusState<UUID?>.Binding) {
        model.focusSetter = { id in binding.wrappedValue = id }
    }
}

/// The visible-response region. On macOS its frame is reported so the recorder can crop the capture to it.
struct TypedCounter: View {
    let model: WorkloadModel

    var body: some View {
        #if WORKLOAD_RUNTIME
        Text("typed \(model.typedCount)")
        #else
        Text("typed \(model.typedCount)")
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { model.counterRect = WRegion(x: $0.minX, y: $0.minY, w: $0.width, h: $0.height) })
        #endif
    }
}

/// The pinned active editor: the typing target.
struct ActiveEditor: View {
    let model: WorkloadModel
    let focus: FocusState<UUID?>.Binding

    var body: some View {
        TextField("Type here", text: Binding(get: { model.active.text }, set: { model.userEdit(model.activeID, $0) }))
            .focused(focus, equals: model.activeID)
    }
}

struct StatusLine: View {
    let model: WorkloadModel

    var body: some View {
        Text("rows \(model.rowTotal)  ops \(model.opsDone)")
    }
}

/// The scrolling content: 199 editable rows in the width-dependent layout.
struct WorkloadRowList: View {
    @Bindable var model: WorkloadModel
    let focus: FocusState<UUID?>.Binding

    var body: some View {
        WorkloadScrollArea(model: model) {
            WorkloadLayout {
                ForEach($model.rows, id: \.id) { row in
                    WorkloadRowCell(row: row, model: model, focus: focus)
                }
            }
        }
    }
}

/// Scrolling content. Windows: the host applies `scrollPhase` to the runtime ScrollView node on every display tick
/// (Graph.scroll), so this is a plain ScrollView. macOS: the model's triangle wave drives ScrollPosition.
struct WorkloadScrollArea<Content: View>: View {
    let model: WorkloadModel
    let content: Content

    init(model: WorkloadModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    #if WORKLOAD_RUNTIME
    var body: some View {
        ScrollView { content }
    }
    #else
    @State private var position = ScrollPosition(y: 0)

    var body: some View {
        ScrollView { content }
            .scrollPosition($position)
            .overlay { ScrollPhaseWatcher(model: model, position: $position) }
    }
    #endif
}

#if !WORKLOAD_RUNTIME
/// Reads `scrollPhase` in its own body so the 60 Hz scroll state never invalidates the root view.
struct ScrollPhaseWatcher: View {
    let model: WorkloadModel
    @Binding var position: ScrollPosition
    var body: some View {
        let phase = model.scrollPhase
        return Color.clear
            .allowsHitTesting(false)
            .onChange(of: phase) { _, new in
                position.scrollTo(y: new * WorkloadScreenMetrics.scrollSpan)
            }
    }
}

public enum WorkloadScreenMetrics {
    /// Scrollable span in points (content height minus viewport) for the pinned window; the Mac host may adjust it.
    nonisolated(unsafe) public static var scrollSpan: CGFloat = 4000
}
#endif
