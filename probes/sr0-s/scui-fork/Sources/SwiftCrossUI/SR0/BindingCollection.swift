import Foundation

// SR0-OVERRIDE O2 (additive API gap): `Binding` to a collection is itself a collection of element
// bindings, and `Binding<Element>` is `Identifiable`, so `ForEach($items) { $item in }` selects the
// existing `ForEach` Identifiable initializer with id-keyed node reuse. Stock SCUI has neither
// (assessment: "ForEach over Binding<[Row]>: not present"). No change to ForEach itself.
#if !SCUI_STOCK_FOREACHBINDING
extension Binding: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

extension Binding: Sequence, Collection, BidirectionalCollection, RandomAccessCollection, MutableCollection
where Value: MutableCollection & RandomAccessCollection {
    public typealias Index = Value.Index
    public typealias Element = Binding<Value.Element>

    public var startIndex: Value.Index { wrappedValue.startIndex }
    public var endIndex: Value.Index { wrappedValue.endIndex }

    public func index(after i: Value.Index) -> Value.Index { wrappedValue.index(after: i) }
    public func index(before i: Value.Index) -> Value.Index { wrappedValue.index(before: i) }

    public subscript(position: Value.Index) -> Binding<Value.Element> {
        get {
            let whole = self
            return Binding<Value.Element>(
                get: { whole.wrappedValue[position] },
                set: { whole.wrappedValue[position] = $0 }
            )
        }
        nonmutating set {
            wrappedValue[position] = newValue.wrappedValue
        }
    }
}

// SwiftUI's `ForEach.init(_: Binding<C>, content: (Binding<C.Element>) -> Content)`. The explicit
// signature is required for the `{ $row in }` projection parameter to type-check. Row bindings are
// resolved by element id, not by index: an index-addressed binding goes stale after an insert above
// or a removal (and traps when a removed row's node still re-evaluates), which is the F1/F4 failure
// mode the SR0 fixtures exist to catch.
func idResolvedBinding<C: RandomAccessCollection & MutableCollection, E: Identifiable>(
    in data: Binding<C>,
    element: Binding<E>
) -> Binding<E> where C.Element == E {
    let id = element.wrappedValue.id
    var last = element.wrappedValue
    return Binding<E>(
        get: {
            if let current = data.wrappedValue.first(where: { $0.id == id }) { last = current }
            return last
        },
        set: { newValue in
            last = newValue
            if let index = data.wrappedValue.firstIndex(where: { $0.id == id }) {
                data.wrappedValue[index] = newValue
            }
        }
    )
}

extension ForEach {
    public init<C: RandomAccessCollection & MutableCollection, E: Identifiable>(
        _ data: Binding<C>,
        @ViewBuilder content: @escaping (Binding<E>) -> Child
    ) where Items == Binding<C>, C.Element == E, ID == E.ID, Child: View {
        self.elements = data
        self.child = { content(idResolvedBinding(in: data, element: $0)) }
        self.idKeyPath = \Binding<E>.id
    }

    public init<C: RandomAccessCollection & MutableCollection, E: Identifiable>(
        _ data: Binding<C>,
        id: KeyPath<E, ID>,
        @ViewBuilder content: @escaping (Binding<E>) -> Child
    ) where Items == Binding<C>, C.Element == E, Child: View {
        self.elements = data
        self.child = { content(idResolvedBinding(in: data, element: $0)) }
        self.idKeyPath = (\Binding<E>.wrappedValue).appending(path: id)
    }
}
#endif
