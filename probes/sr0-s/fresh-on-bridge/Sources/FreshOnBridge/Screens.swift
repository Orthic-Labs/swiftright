import Foundation
import Observation
import SwiftRightRuntime

// Ports of probes/sr0-o/fixtures Screens/*.swift and Common/SharedViews.swift onto SwiftRightRuntime.
// Runtime-supported API only. Gaps (no LazyVStack, onChange, toolbar, task(id:), animation completion,
// reduce-motion env, accessibilityIdentifier) are NOT faked here; the self-test marks them BLOCKED.

/// Common chrome: an insert button (the Mac toolbar, placed in the body because the runtime has no toolbar)
/// and the root appear log. The content receives the screen's focus binding.
struct FixtureChrome<Content: View>: View {
    @Bindable var model: RowModel
    @FocusState private var focus: UUID?
    let content: (FocusState<UUID?>.Binding) -> Content

    init(model: RowModel, @ViewBuilder content: @escaping (FocusState<UUID?>.Binding) -> Content) {
        self._model = Bindable(wrappedValue: model)
        self.content = content
    }

    var body: some View {
        let _ = model.registerFocus($focus)
        VStack(alignment: .leading, spacing: 8) {
            Button("Insert above", action: { model.requestInsert() })
            content($focus)
        }
        .padding(.all, 16)
        .onAppear {
            model.log.emit("lifecycle", node: "window", payload: ["phase": "root-appear"])
        }
    }
}

/// One editable row. Its @State is per identity: a row keeps its counter only where the container keeps state.
struct EditableRowView: View {
    let row: Binding<Row>
    let model: RowModel
    let focus: FocusState<UUID?>.Binding
    var rowTask = false
    var showDelete = false
    @State private var localEdits = 0

    var body: some View {
        let id = row.wrappedValue.id
        let text = row.text
        let edits = $localEdits
        let _ = model.registerTextInput(id) { newValue in
            text.wrappedValue = newValue
            edits.wrappedValue += 1
            model.log.emit("state", node: id.uuidString, payload: ["op": "edit", "text": newValue])
            model.log.emit("lifecycle", node: id.uuidString, payload: ["phase": "local-edit", "local": edits.wrappedValue])
        }
        HStack {
            TextField("Row", text: Binding(get: { text.wrappedValue }, set: { model.editText(id, $0) }))
                .focused(focus, equals: id)
            Text("local \(localEdits)")
            if showDelete {
                Button("Delete", action: { model.removeRow(id) })
            }
        }
        // The task modifier is innermost: teardown runs the outer onDisappear before the inner task cancel,
        // the order the Mac oracle records (disappear, then cancel).
        .task {
            if rowTask { await model.runRowLoad(id) }
        }
        .onAppear {
            let controls: [String] = showDelete ? ["field", "delete"] : ["field"]
            model.log.emit("lifecycle", node: id.uuidString, payload: [
                "phase": "appear", "local": edits.wrappedValue, "controls": controls,
            ])
        }
        .onDisappear {
            model.log.emit("lifecycle", node: id.uuidString, payload: ["phase": "disappear", "local": edits.wrappedValue])
        }
    }
}

/// Editable rows in a List (the F1-F4, F6-F9 container). List keeps removed rows' @State (SR0-S F3 alignment).
struct RowList: View {
    @Bindable var model: RowModel
    let focus: FocusState<UUID?>.Binding
    var rowTasks = false
    var showDelete = false

    var body: some View {
        List {
            ForEach($model.rows, id: \.id) { row in
                EditableRowView(row: row, model: model, focus: focus, rowTask: rowTasks, showDelete: showDelete)
            }
            .onMove { offsets, destination in
                model.moveRow(from: offsets, to: destination)
            }
        }
    }
}

/// F3 container variants that the runtime supports. LazyVStack needs a ScrollView and a lazy primitive
/// (neither exists in the runtime), so the `lazy` variant is not a Screen here.
struct RowStack: View {
    @Bindable var model: RowModel
    let focus: FocusState<UUID?>.Binding
    let container: F3Container
    var rowTasks = false

    var body: some View {
        if container == .vstack {
            VStack(alignment: .leading, spacing: 8) {
                ForEach($model.rows, id: \.id) { row in
                    EditableRowView(row: row, model: model, focus: focus, rowTask: rowTasks)
                }
            }
        } else {
            RowList(model: model, focus: focus, rowTasks: rowTasks)
        }
    }
}

/// Width-dependent custom layout (port of F5Screen.swift). Subset: sizeThatFits and placeSubviews.
struct WidthDependentLayout: Layout {
    let log: EventLog
    static let wideThreshold: CGFloat = 560
    static let gutter: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> LayoutSize {
        let width = proposal.width ?? 480
        let frames = Self.plan(width: width, subviews: subviews, originX: 0, originY: 0)
        let height = frames.map(\.maxY).max() ?? 0
        return LayoutSize(width: width, height: height)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let frames = Self.plan(width: bounds.width, subviews: subviews, originX: bounds.minX, originY: bounds.minY)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: frames[index].origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(frames[index].size)
            )
        }
        let wide = bounds.width >= Self.wideThreshold
        let outside = frames.filter { !Self.isContained($0, in: bounds) }
        let contained = outside.isEmpty
        let signature = "\(wide)|" + frames.map { Self.describe($0) }.joined(separator: ";")
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

    static func isContained(_ frame: LayoutRect, in bounds: LayoutRect) -> Bool {
        let tolerance: CGFloat = 0.5
        return frame.minX >= bounds.minX - tolerance && frame.maxX <= bounds.maxX + tolerance
            && frame.minY >= bounds.minY - tolerance && frame.maxY <= bounds.maxY + tolerance
    }

    static func describe(_ rect: LayoutRect) -> String {
        "x=\(rect.minX),y=\(rect.minY),w=\(rect.width),h=\(rect.height)"
    }

    static func plan(width: CGFloat, subviews: Subviews, originX: CGFloat, originY: CGFloat) -> [LayoutRect] {
        let columns = width >= wideThreshold ? 2 : 1
        let columnWidth = (width - gutter * CGFloat(columns - 1)) / CGFloat(columns)
        var frames: [LayoutRect] = []
        var y = originY
        var rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let column = index % columns
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let x = originX + CGFloat(column) * (columnWidth + gutter)
            frames.append(LayoutRect(origin: LayoutPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            if column == columns - 1 {
                y += rowHeight + gutter
                rowHeight = 0
            }
        }
        return frames
    }
}

// MARK: - Screens (one per fixture)

/// F1: surviving-row identity. Engine-driven insert above the active edit, started at appear.
struct F1Root: View {
    @Bindable var model: RowModel
    var body: some View {
        FixtureChrome(model: model) { focus in
            RowList(model: model, focus: focus)
        }
        .task { await model.runInsertAbove(key: "insert-above", slot: 99) }
    }
}

/// F2: reorder. Identity and focus preserved across a move.
struct F2Root: View {
    @Bindable var model: RowModel
    var body: some View {
        FixtureChrome(model: model) { focus in
            RowList(model: model, focus: focus)
        }
    }
}

/// F3: removal tears rows down; reinsertion with the same UUID. The container is a variant axis.
struct F3Root: View {
    @Bindable var model: RowModel
    let container: F3Container
    var body: some View {
        FixtureChrome(model: model) { focus in
            RowStack(model: model, focus: focus, container: container, rowTasks: true)
        }
    }
}

/// F4: each row runs a guarded engine task; removal happens before the engine completes.
struct F4Root: View {
    @Bindable var model: RowModel
    var body: some View {
        FixtureChrome(model: model) { focus in
            RowList(model: model, focus: focus, rowTasks: true)
        }
    }
}

/// F5: width-dependent layout with an async row update and an async insert while the window resizes.
struct F5Root: View {
    @Bindable var model: RowModel
    var body: some View {
        FixtureChrome(model: model) { focus in
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

/// F6: overlapping animated inserts; reduced-motion policy (variant flag only; see RESULT.md).
struct F6Root: View {
    @Bindable var model: RowModel
    var body: some View {
        FixtureChrome(model: model) { focus in
            RowList(model: model, focus: focus)
        }
        .onAppear { model.applyMotionPolicy() }
    }
}

/// F7: IME placeholder. Composition is not exercised (runtime has no marked text).
struct F7Root: View {
    @Bindable var model: RowModel
    var body: some View {
        FixtureChrome(model: model) { focus in
            VStack(alignment: .leading, spacing: 8) {
                Text("IME placeholder: composition is driven out-of-process")
                RowList(model: model, focus: focus)
            }
        }
        .task { await model.runInsertAbove(key: "insert-above", slot: 99) }
    }
}

/// F8: accessibility surface. Every row exposes a text field and a labelled Delete button.
struct F8Root: View {
    @Bindable var model: RowModel
    var body: some View {
        FixtureChrome(model: model) { focus in
            RowList(model: model, focus: focus, showDelete: true)
        }
    }
}

/// F9: window teardown with live row tasks and a screen-level task. The probe's deinit records tree release.
struct F9Root: View {
    @Bindable var model: RowModel
    let withTasks: Bool
    @State private var probe: TreeProbe?

    var body: some View {
        FixtureChrome(model: model) { focus in
            RowList(model: model, focus: focus, rowTasks: withTasks)
        }
        .task {
            if withTasks { await model.runScreenSync() }
        }
        .onAppear {
            if probe == nil { probe = TreeProbe(log: model.log) }
        }
    }
}

/// Lifetime probe for the screen's view state. Its deinit records that the tree was released.
final class TreeProbe {
    private let log: EventLog

    init(log: EventLog) {
        self.log = log
    }

    deinit {
        log.emit("lifecycle", node: "tree", payload: ["phase": "released"])
    }
}

/// Builds the retained graph for the selected fixture.
@MainActor
func makeGraph(options: FixtureOptions, model: RowModel, measurer: any TextMeasurer, scale: CGFloat) -> Graph {
    switch options.fixture {
    case .F1: return Graph(F1Root(model: model), measurer: measurer, scale: scale)
    case .F2: return Graph(F2Root(model: model), measurer: measurer, scale: scale)
    case .F3: return Graph(F3Root(model: model, container: options.f3Container), measurer: measurer, scale: scale)
    case .F4: return Graph(F4Root(model: model), measurer: measurer, scale: scale)
    case .F5: return Graph(F5Root(model: model), measurer: measurer, scale: scale)
    case .F6: return Graph(F6Root(model: model), measurer: measurer, scale: scale)
    case .F7: return Graph(F7Root(model: model), measurer: measurer, scale: scale)
    case .F8: return Graph(F8Root(model: model), measurer: measurer, scale: scale)
    case .F9: return Graph(F9Root(model: model, withTasks: !options.f9NoTasks), measurer: measurer, scale: scale)
    }
}
