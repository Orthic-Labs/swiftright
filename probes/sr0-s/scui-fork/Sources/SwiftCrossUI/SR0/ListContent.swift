import Foundation

// SR0-OVERRIDE O3 (new view API + semantics): `List { ForEach(...) }` with SwiftUI semantics.
// Stock `List` takes `(data, id:, selection:, rowContent:)` and keeps rows by *index*
// (Views/List.swift: `rowContent(data[index])`), so an insert above re-binds every row's node.
// The fork adds the ViewBuilder initializer: content is one row-host whose `ForEach` children keep
// id-keyed identity, and which sets `retainsRemovedRowState` so `ForEach` hands a reinserted id its
// old `@State` (the macOS 27 oracle behaviour for `List`; `VStack` resets).
#if !SCUI_STOCK_LIST
struct RetainsRemovedRowStateKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    var retainsRemovedRowState: Bool {
        get { self[RetainsRemovedRowStateKey.self] }
        set { self[RetainsRemovedRowStateKey.self] = newValue }
    }
}

public struct ListRows<Content: View>: View {
    var content: Content

    public var body: some View {
        VStack(spacing: 0) {
            content
        }
        .environment(\.retainsRemovedRowState, true)
    }
}

extension List where SelectionValue == Never {
    public init<Content: View>(@ViewBuilder content: @escaping () -> Content)
    where RowView == ListRows<Content> {
        self.selection = Binding(get: { nil }, set: { _ in })
        self.rowContent = { _ in ListRows(content: content()) }
        self.associatedSelectionValue = { _ in fatalError("List(content:) has no selection") }
        self.find = { _ in nil }
        self.rowCount = 1
    }
}

/// Views whose `@State` is lifecycle bookkeeping and is excluded from row-state restore.
protocol EphemeralStateView {}
extension OnChangeModifier: EphemeralStateView {}
#endif
