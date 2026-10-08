import Foundation
import Observation
#if os(macOS)
import SwiftUI
import SwiftRightUI
#else
import SwiftRightUI
#endif

struct Row: Identifiable, Equatable {
    let id: UUID
    var text: String
}

@MainActor
@Observable
final class RowStore {
    var rows: [Row] = [
        Row(id: UUID(), text: "First"),
        Row(id: UUID(), text: "Second"),
    ]

    func addRow() {
        rows.append(Row(id: UUID(), text: "Added"))
    }

    func insertLater() async {
        try? await Task.sleep(nanoseconds: 1_000_000)
        rows.insert(Row(id: UUID(), text: "Async"), at: 0)
    }

    func move(from offsets: IndexSet, to destination: Int) {
        rows.move(fromOffsets: offsets, toOffset: destination)
    }
}

struct WidthDependentLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        var height: CGFloat = 0
        for subview in subviews {
            height += subview.sizeThatFits(.unspecified).height
        }
        return CGSize(width: proposal.width ?? 320, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(.unspecified).height
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: .unspecified)
            y += height
        }
    }
}

struct ReorderableEditorScreen: View {
    @State private var store = RowStore()
    @FocusState private var focus: UUID?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var editable = store
        VStack(alignment: .leading, spacing: 8) {
            Text("SDK \(SwiftRightUI.sdkVersion)")
            List {
                ForEach($editable.rows) { $row in
                    TextField("Row", text: $row.text)
                        .focused($focus, equals: row.id)
                }
                .onMove { offsets, destination in
                    store.move(from: offsets, to: destination)
                }
            }
            Button("Add row") {
                store.addRow()
            }
            WidthDependentLayout {
                Text("Rows: \(store.rows.count)")
                if store.rows.isEmpty {
                    Text("Empty")
                } else {
                    Text("Has rows")
                }
                if colorScheme == .dark {
                    Text("Dark")
                }
            }
            .padding()
        }
        .padding()
        .animation(.default, value: store.rows.count)
        .onAppear {
            focus = nil
        }
        .task {
            await store.insertLater()
        }
    }
}
