import Foundation

let onPreferenceChangeKey = "<onPreferenceChange>"

/// A value that flows from descendants toward ancestors in a view tree.
public protocol PreferenceKey {
    associatedtype Value
    static var defaultValue: Value { get }
    static func reduce(value: inout Value, nextValue: () -> Value)
}

extension PreferenceKey where Value: ExpressibleByNilLiteral {
    /// Optional-valued keys need no explicit default: it is `nil`.
    /// Apple: https://developer.apple.com/documentation/swiftui/preferencekey/defaultvalue-7pt4w
    public static var defaultValue: Value { nil }
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

struct PreferenceContribution {
    let apply: (inout PreferenceValues) -> Void

    init<Key: PreferenceKey>(_ value: Key.Value, for key: Key.Type) {
        apply = { values in values.reduce(value, for: key) }
    }
}

struct PreferenceObserver {
    let key: ObjectIdentifier
    let defaultValue: Any
    let value: (PreferenceValues) -> Any
    let equals: (Any, Any) -> Bool
    let action: (Any) -> Void

    init<Key: PreferenceKey>(_ key: Key.Type, action: @escaping (Key.Value) -> Void) where Key.Value: Equatable {
        self.key = ObjectIdentifier(key)
        defaultValue = Key.defaultValue
        value = { $0.value(for: key) }
        equals = { ($0 as? Key.Value) == ($1 as? Key.Value) }
        self.action = { if let value = $0 as? Key.Value { action(value) } }
    }
}

final class PreferenceObserverBaseline {
    let key: ObjectIdentifier
    var value: Any

    init(key: ObjectIdentifier, value: Any) {
        self.key = key
        self.value = value
    }
}
