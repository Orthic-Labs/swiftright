import Foundation

// Issue #60 (SR1 backlog), first pass: the data-driven List initialisers.
//
//   List(data, id: \.key) { row in ... }
//   List(data) { row in ... }                       data elements are Identifiable
//   List(0..<n) { i in ... }
//   List(data, id: \.key, selection: $one) { ... }  single selection, Binding<SelectionValue?>
//   List(data, id: \.key, selection: $many) { ... } multiple selection, Binding<Set<SelectionValue>>
//   List(data, selection: $one) { ... }             Identifiable data
//
// Each one is a List whose content is a `ForEach` over the data, as in SwiftUI. For the selection forms every row is tagged with its id (SwiftUI selects a data row by
// its id), so a row selects and keyboard-navigates like a `.tag(id)` row of `List(selection:)`; the selection value type should equal the id type, as SwiftUI needs.
// An explicit `.tag(_:)` the row content sets itself sits inside the id tag and does not override it (an adaptation: SwiftUI prefers the explicit tag).

/// A List row tagged with its data id; the wrapper the selection initialisers give each row.
/// Apple: https://developer.apple.com/documentation/swiftui/view/tag(_:)
public struct _ListRowTag<Content: View>: View, PrimitiveView {
    let tag: AnyHashable
    let content: Content

    init(tag: AnyHashable, content: Content) {
        self.tag = tag
        self.content = content
    }

    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .modifier(.tag(tag)) }
    var nodeContent: (any View)? { content }
}

@MainActor
private func singleSelection<V: Hashable>(_ binding: Binding<V?>) -> SelectionAccess {
    SelectionAccess(
        multiple: false,
        current: { binding.wrappedValue.map { Set([AnyHashable($0)]) } ?? [] },
        write: { set in binding.wrappedValue = set.first?.base as? V }
    )
}

@MainActor
private func multipleSelection<V: Hashable>(_ binding: Binding<Set<V>>) -> SelectionAccess {
    SelectionAccess(
        multiple: true,
        current: { Set(binding.wrappedValue.map { AnyHashable($0) }) },
        write: { set in binding.wrappedValue = Set(set.compactMap { $0.base as? V }) }
    )
}

// MARK: - Without selection

extension List where SelectionValue == Never {
    /// Apple: https://developer.apple.com/documentation/swiftui/list/init(_:id:rowcontent:)
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.init(content: ForEach<Data, ID, RowContent>(items: data, idOf: { $0[keyPath: id] }, makeContent: rowContent))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/list/init(_:rowcontent:)
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.init(content: ForEach<Data, Data.Element.ID, RowContent>(items: data, idOf: { $0.id }, makeContent: rowContent))
    }

    /// A constant range of rows. Apple: https://developer.apple.com/documentation/swiftui/list/init(_:rowcontent:)
    public init<RowContent: View>(
        _ data: Range<Int>,
        @ViewBuilder rowContent: @escaping (Int) -> RowContent
    ) where Content == ForEach<Range<Int>, Int, RowContent> {
        self.init(content: ForEach<Range<Int>, Int, RowContent>(items: data, idOf: { $0 }, makeContent: rowContent))
    }
}

// MARK: - With selection

extension List where SelectionValue: Hashable {
    /// Single selection over data rows keyed by `id`. Apple: https://developer.apple.com/documentation/swiftui/list/init(_:id:selection:rowcontent:)
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, _ListRowTag<RowContent>> {
        let rows = ForEach<Data, ID, _ListRowTag<RowContent>>(
            items: data,
            idOf: { $0[keyPath: id] },
            makeContent: { _ListRowTag(tag: AnyHashable($0[keyPath: id]), content: rowContent($0)) }
        )
        self.init(content: rows, selectionAccess: selection.map { singleSelection($0) })
    }

    /// Multiple selection over data rows keyed by `id`. Apple: https://developer.apple.com/documentation/swiftui/list/init(_:id:selection:rowcontent:)
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, _ListRowTag<RowContent>> {
        let rows = ForEach<Data, ID, _ListRowTag<RowContent>>(
            items: data,
            idOf: { $0[keyPath: id] },
            makeContent: { _ListRowTag(tag: AnyHashable($0[keyPath: id]), content: rowContent($0)) }
        )
        self.init(content: rows, selectionAccess: selection.map { multipleSelection($0) })
    }

    /// Single selection over Identifiable data. Apple: https://developer.apple.com/documentation/swiftui/list/init(_:selection:rowcontent:)
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, _ListRowTag<RowContent>>, Data.Element: Identifiable {
        let rows = ForEach<Data, Data.Element.ID, _ListRowTag<RowContent>>(
            items: data,
            idOf: { $0.id },
            makeContent: { _ListRowTag(tag: AnyHashable($0.id), content: rowContent($0)) }
        )
        self.init(content: rows, selectionAccess: selection.map { singleSelection($0) })
    }

    /// Multiple selection over Identifiable data. Apple: https://developer.apple.com/documentation/swiftui/list/init(_:selection:rowcontent:)
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, _ListRowTag<RowContent>>, Data.Element: Identifiable {
        let rows = ForEach<Data, Data.Element.ID, _ListRowTag<RowContent>>(
            items: data,
            idOf: { $0.id },
            makeContent: { _ListRowTag(tag: AnyHashable($0.id), content: rowContent($0)) }
        )
        self.init(content: rows, selectionAccess: selection.map { multipleSelection($0) })
    }
}
