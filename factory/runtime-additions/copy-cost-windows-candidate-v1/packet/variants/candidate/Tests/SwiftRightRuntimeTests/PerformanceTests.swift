import Foundation
import Observation
@testable import SwiftRightRuntime
import XCTest

// Scaling of the commit path (SR0 R10 diagnosis). The SR0 section 11 workload put 200 rows through the runtime and a
// commit took 0.3 to 0.4 s: layout asked every subtree several times per pass, every query resolved a row binding by
// scanning the whole array, node identity hashed whole type names, and every commit re-derived everything. These tests pin
// the fixed behaviour with work counters (exact, build-independent) and with wall-clock guards sized for each build mode.

struct PerfRow: Identifiable, Equatable {
    let id: UUID
    var slot: Int
    var text: String
    var detail: String
}

@Observable
@MainActor
final class PerfStore {
    var rows: [PerfRow]
    var typed = 0
    var activeText = ""
    var tick = 0
    var other = 0

    init(rows count: Int) {
        rows = (0..<count).map { slot in
            PerfRow(id: UUID(uuidString: String(format: "6E000000-0000-4000-8000-%012d", slot))!, slot: slot,
                    text: "Row \(slot)", detail: perfDetail(slot: slot, version: 0))
        }
    }
}

func perfDetail(slot: Int, version: Int) -> String {
    version % 2 == 0
        ? "Item \(slot) ready (v\(version))"
        : "Item \(slot) queued for review (v\(version)): a longer description that wraps at the narrow column width."
}

/// Two columns from 560 pt, one below; row heights depend on the column width through each row's wrapped detail text.
struct PerfLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> LayoutSize {
        let width = proposal.width ?? 480
        let frames = Self.plan(width: width, subviews: subviews)
        return LayoutSize(width: width, height: frames.map { $0.maxY }.max() ?? 0)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let frames = Self.plan(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let f = frames[index]
            subview.place(at: LayoutPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(f.size))
        }
    }

    static func plan(width: CGFloat, subviews: Subviews) -> [LayoutRect] {
        let columns = width >= 560 ? 2 : 1
        let columnWidth = (width - 8 * CGFloat(columns - 1)) / CGFloat(columns)
        var frames: [LayoutRect] = []
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let column = index % columns
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            frames.append(LayoutRect(x: CGFloat(column) * (columnWidth + 8), y: y, width: columnWidth, height: size.height))
            rowHeight = max(rowHeight, size.height)
            if column == columns - 1 {
                y += rowHeight + 8
                rowHeight = 0
            }
        }
        return frames
    }
}

struct PerfRowCell: View {
    let row: Binding<PerfRow>
    let store: PerfStore
    let focus: FocusState<UUID?>.Binding

    var body: some View {
        let id = row.wrappedValue.id
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(row.wrappedValue.slot)")
                TextField("Row", text: row.text).focused(focus, equals: id)
            }
            Text(row.wrappedValue.detail)
        }
        .task {}
        .onAppear {}
        .onDisappear {}
    }
}

/// Header views read their own state, so typing never touches the rows (the shape of the workload screen).
struct PerfCounter: View {
    let store: PerfStore
    var body: some View { Text("typed \(store.typed)") }
}

struct PerfEditor: View {
    let store: PerfStore
    let focus: FocusState<UUID?>.Binding
    var body: some View {
        TextField("Type here", text: Binding(get: { store.activeText }, set: { store.activeText = $0 }))
            .focused(focus, equals: UUID(uuidString: "6E0A0000-0000-4000-8000-000000000000"))
    }
}

struct PerfRows: View {
    @Bindable var store: PerfStore
    let focus: FocusState<UUID?>.Binding
    var body: some View {
        ScrollView {
            PerfLayout().callAsFunction {
                ForEach($store.rows, id: \.id) { row in
                    PerfRowCell(row: row, store: store, focus: focus)
                }
            }
        }
    }
}

struct PerfScreen: View {
    @Bindable var store: PerfStore
    @FocusState private var focus: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PerfCounter(store: store)
            PerfEditor(store: store, focus: $focus)
            PerfRows(store: store, focus: $focus)
        }
        .padding(.all, 12)
    }
}

/// Reads `watched` in its body and nothing else; `other` changes re-evaluate it through its parent.
struct WatcherProbe: View {
    let store: PerfStore
    var body: some View { Text("watched \(store.typed)") }
}

struct ParentProbe: View {
    let store: PerfStore
    var body: some View {
        VStack {
            Text("other \(store.other)")
            WatcherProbe(store: store)
        }
    }
}

@MainActor
private func flatten(_ root: ResolvedNode?) -> [String] {
    var out: [String] = []
    func visit(_ node: ResolvedNode) {
        out.append("\(node.id)|\(node.kind)|\(node.text ?? "-")|\(node.frame)|\(node.opacity)|\(node.accessibility)")
        node.children.forEach(visit)
    }
    if let root { visit(root) }
    return out
}

@MainActor
final class PerformanceTests: XCTestCase {
    static let rowCount = 200

    /// A graph over a fresh 200-row store, flushed once, with phase counters on.
    private func makeGraph(width: CGFloat = 960, height: CGFloat = 640) -> (Graph, PerfStore, FixedAdvanceTextMeasurer) {
        let store = PerfStore(rows: Self.rowCount)
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(PerfScreen(store: store), measurer: measurer, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: width, height: height)
        graph.flush()
        graph.profile = GraphProfile()
        return (graph, store, measurer)
    }

    private var isOptimized: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    /// Median wall time in milliseconds of `body`, over `runs` calls after `warmup` calls.
    private func medianMS(runs: Int = 25, warmup: Int = 5, _ body: (Int) -> Void) -> Double {
        for i in 0..<warmup { body(i) }
        var samples: [Double] = []
        for i in 0..<runs {
            let start = DispatchTime.now().uptimeNanoseconds
            body(warmup + i)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }
        return samples.sorted()[samples.count / 2]
    }

    // MARK: work counters

    func testTypingEvaluatesTheHeaderOnlyAndNeverMeasuresRows() {
        let (graph, store, measurer) = makeGraph()
        let requests = measurer.requests.count
        store.typed += 1
        store.activeText += "x"
        graph.flush()
        let profile = graph.profile!
        XCTAssertEqual(profile.commits, 1, "one commit per flush")
        XCTAssertLessThanOrEqual(profile.evaluations, 8, "typing re-evaluates the counter and the editor, not the \(Self.rowCount) rows")
        XCTAssertLessThanOrEqual(measurer.requests.count - requests, 2, "only the two changed texts are measured")
    }

    func testRowEditWorkIsLinearAndMeasuresOnlyChangedText() {
        let (graph, store, measurer) = makeGraph()
        let requests = measurer.requests.count
        store.rows[17].text = "Row 17 edited"
        graph.flush()
        let profile = graph.profile!
        // Every row reads `rows`, so every row is evaluated once: a bounded number of nodes per row, not a growing one.
        XCTAssertLessThanOrEqual(profile.evaluations, 12 * Self.rowCount + 20)
        let measured = measurer.requests.dropFirst(requests).map(\.text)
        XCTAssertEqual(measured, ["Row 17 edited"], "unchanged texts hit the measurement memo")
    }

    func testScrollOnlyCommitEvaluatesAndMeasuresNothing() {
        let (graph, _, measurer) = makeGraph()
        let scrollID = graph.ids(ofKind: "ScrollView")[0]
        let requests = measurer.requests.count
        graph.scroll(scrollID, to: 120)
        graph.flush()
        graph.scroll(scrollID, to: 240)
        graph.flush()
        XCTAssertEqual(graph.profile!.evaluations, 0)
        XCTAssertEqual(measurer.requests.count, requests, "no text is measured when only the scroll offset moved")
        XCTAssertEqual(graph.scrollOffset(scrollID), 240)
    }

    func testRepeatedEvaluationDoesNotStackObservationRegistrations() {
        let store = PerfStore(rows: 1)
        let graph = Graph(ParentProbe(store: store))
        graph.flush()
        // The parent is re-evaluated 40 times; each time it evaluates the watcher again without `typed` having changed.
        for _ in 0..<40 {
            store.other += 1
            graph.flush()
        }
        let before = graph.observationCallbacks
        store.typed += 1
        graph.flush()
        XCTAssertEqual(graph.observationCallbacks - before, 1, "one live registration on `typed`, not one per evaluation")
        XCTAssertEqual(graph.ids(ofKind: "Text").compactMap { id in everyNode(graph.snapshot()).first { $0.id == id }?.text },
                       ["other 40", "watched 1"])
    }

    func testRemovedRowsLeaveNoObservationRegistrationsBehind() {
        let (graph, store, _) = makeGraph()
        for _ in 0..<20 {
            store.rows.removeFirst()
            graph.flush()
        }
        let before = graph.observationCallbacks
        store.rows[0].text = "changed"
        graph.flush()
        // Only the live rows (and their container) react: at most a couple of registrations per live row.
        XCTAssertLessThanOrEqual(graph.observationCallbacks - before, 3 * store.rows.count + 4)
    }

    // MARK: wall clock

    func testSingleRowEditCommitTime() {
        let (graph, store, _) = makeGraph()
        let typing = medianMS { i in
            store.typed += 1
            store.activeText = String(repeating: "m", count: i % 30)
            graph.flush()
        }
        let scroll = medianMS { i in
            graph.scroll(graph.ids(ofKind: "ScrollView")[0], to: CGFloat(i * 7))
            graph.flush()
        }
        let rowEdit = medianMS { i in
            store.rows[(i * 37) % store.rows.count].text = "Row edited \(i)"
            graph.flush()
        }
        print("PERF 200-row commit medians (ms): typing \(typing), scroll-only \(scroll), row edit \(rowEdit)  optimized=\(isOptimized)")
        // Optimized build: the bounds the fix targets (before it each of these was 300 to 400 ms). The debug build has no
        // inlining or specialisation, so its bounds only catch an algorithmic regression (orders of magnitude, not factors).
        XCTAssertLessThan(typing, isOptimized ? 2 : 80, "typing commit")
        XCTAssertLessThan(scroll, isOptimized ? 4 : 100, "scroll-only commit")
        XCTAssertLessThan(rowEdit, isOptimized ? 15 : 250, "row edit commit (every row cell is re-evaluated)")
    }

    // MARK: equivalence

    /// Layout and resolution are cached between commits. After every edit of a long random sequence, the incrementally updated
    /// graph must equal a graph built from scratch over the same data.
    func testIncrementalCommitsEqualAFreshGraph() {
        var seed: UInt64 = 0x5EED_0000_0000_0001
        func next(_ n: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(n))
        }
        let (graph, store, _) = makeGraph()
        var width: CGFloat = 960
        for step in 0..<60 {
            switch next(6) {
            case 0:
                let i = next(store.rows.count)
                store.rows[i].detail = perfDetail(slot: store.rows[i].slot, version: step)
            case 1:
                store.rows[next(store.rows.count)].text = String(repeating: "w", count: 1 + next(30))
            case 2:
                let item = store.rows.remove(at: next(store.rows.count))
                store.rows.insert(item, at: next(store.rows.count + 1))
            case 3:
                let slot = 1000 + step
                store.rows.insert(PerfRow(id: UUID(uuidString: String(format: "6E0B0000-0000-4000-8000-%012d", slot))!, slot: slot,
                                          text: "New \(step)", detail: perfDetail(slot: slot, version: step)), at: next(store.rows.count))
                store.rows.remove(at: next(store.rows.count))
            case 4:
                width = [480, 640, 960, 1200][next(4)]
                graph.rootProposal = ProposedViewSize(width: width, height: 640)
                store.other += 1
            default:
                store.typed += 1
                store.activeText = String(repeating: "t", count: next(25))
            }
            graph.flush()
            if step % 6 == 5 {
                let fresh = Graph(PerfScreen(store: store), measurer: FixedAdvanceTextMeasurer(), scale: 2.5)
                fresh.rootProposal = ProposedViewSize(width: width, height: 640)
                fresh.flush()
                let incremental = flatten(graph.snapshot()), rebuilt = flatten(fresh.snapshot())
                XCTAssertEqual(incremental.count, rebuilt.count, "step \(step): node count")
                if let at = incremental.indices.first(where: { $0 < rebuilt.count && incremental[$0] != rebuilt[$0] }) {
                    XCTFail("step \(step): first difference at node \(at)\n  incremental: \(incremental[at])\n  fresh:       \(rebuilt[at])")
                }
                fresh.tearDown()
            }
        }
    }
}
