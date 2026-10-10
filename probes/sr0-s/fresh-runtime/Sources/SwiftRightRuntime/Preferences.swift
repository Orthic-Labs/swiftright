import Foundation

/// A value that flows from descendants toward ancestors in a view tree.
public protocol PreferenceKey {
    associatedtype Value
    static var defaultValue: Value { get }
    static func reduce(value: inout Value, nextValue: () -> Value)
}

/// Type-erased preference values retained on graph nodes. Values stay typed at the API boundary;
/// reduction invokes the originating key's implementation.
struct PreferenceValues {
    private protocol Entry {
        var rawValue: Any { get }
        func reducing(with next: any Entry) -> any Entry
    }

    private struct TypedEntry<Key: PreferenceKey>: Entry {
        let value: Key.Value
        var rawValue: Any { value }

        func reducing(with next: any Entry) -> any Entry {
            guard let next = next as? TypedEntry<Key> else { return self }
            var result = value
            Key.reduce(value: &result, nextValue: { next.value })
            return TypedEntry<Key>(value: result)
        }
    }

    private var entries: [ObjectIdentifier: any Entry] = [:]

    func value<Key: PreferenceKey>(for key: Key.Type) -> Key.Value {
        entries[ObjectIdentifier(key)]?.rawValue as? Key.Value ?? Key.defaultValue
    }

    mutating func set<Key: PreferenceKey>(_ value: Key.Value, for key: Key.Type) {
        entries[ObjectIdentifier(key)] = TypedEntry<Key>(value: value)
    }

    mutating func reduce<Key: PreferenceKey>(_ value: Key.Value, for key: Key.Type) {
        let identifier = ObjectIdentifier(key)
        let next = TypedEntry<Key>(value: value)
        entries[identifier] = entries[identifier]?.reducing(with: next) ?? next
    }

    mutating func merge(_ next: PreferenceValues) {
        for (identifier, nextEntry) in next.entries {
            entries[identifier] = entries[identifier]?.reducing(with: nextEntry) ?? nextEntry
        }
    }

    var isEmpty: Bool { entries.isEmpty }
}
