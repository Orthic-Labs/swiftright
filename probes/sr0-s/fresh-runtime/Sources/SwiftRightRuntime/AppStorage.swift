import Foundation

// Issue #82 (SR2 S2): AppStorage. UserDefaults is the source of truth: a read goes to the store, a write goes to the store and touches this view's state cell so the view
// is re-evaluated; another view of the same key sees the new value when it next evaluates. No change observation of writes made outside the process or by other code
// (KVO) is modelled. Supported value types are those SwiftUI supports: Bool, Int, Double, String, URL, Data, and RawRepresentable with Int or String raw values;
// an optional of each (nil removes the key).

/// A value `AppStorage` can keep in UserDefaults.
public protocol AppStorageValue {
    static func read(_ defaults: UserDefaults, _ key: String) -> Self?
    func write(_ defaults: UserDefaults, _ key: String)
}

extension Bool: AppStorageValue {
    public static func read(_ d: UserDefaults, _ k: String) -> Bool? { d.object(forKey: k) == nil ? nil : d.bool(forKey: k) }
    public func write(_ d: UserDefaults, _ k: String) { d.set(self, forKey: k) }
}
extension Int: AppStorageValue {
    public static func read(_ d: UserDefaults, _ k: String) -> Int? { d.object(forKey: k) == nil ? nil : d.integer(forKey: k) }
    public func write(_ d: UserDefaults, _ k: String) { d.set(self, forKey: k) }
}
extension Double: AppStorageValue {
    public static func read(_ d: UserDefaults, _ k: String) -> Double? { d.object(forKey: k) == nil ? nil : d.double(forKey: k) }
    public func write(_ d: UserDefaults, _ k: String) { d.set(self, forKey: k) }
}
extension String: AppStorageValue {
    public static func read(_ d: UserDefaults, _ k: String) -> String? { d.string(forKey: k) }
    public func write(_ d: UserDefaults, _ k: String) { d.set(self, forKey: k) }
}
extension URL: AppStorageValue {
    public static func read(_ d: UserDefaults, _ k: String) -> URL? { d.string(forKey: k).flatMap { URL(string: $0) } }
    public func write(_ d: UserDefaults, _ k: String) { d.set(absoluteString, forKey: k) }
}
extension Data: AppStorageValue {
    public static func read(_ d: UserDefaults, _ k: String) -> Data? { d.data(forKey: k) }
    public func write(_ d: UserDefaults, _ k: String) { d.set(self, forKey: k) }
}

/// Apple: https://developer.apple.com/documentation/swiftui/appstorage
@propertyWrapper
public struct AppStorage<Value>: DynamicPropertyStorage {
    let key: String
    let defaultValue: Value
    let store: UserDefaults
    let reader: (UserDefaults, String) -> Value?
    let writer: (UserDefaults, String, Value) -> Void
    let cell = StateCell<Int>(0)

    @MainActor public var wrappedValue: Value {
        get { _ = cell.resolved.value; return reader(store, key) ?? defaultValue }
        nonmutating set { writer(store, key, newValue); cell.resolved.value += 1 }
    }

    @MainActor public var projectedValue: Binding<Value> {
        let this = self
        return Binding(get: { this.wrappedValue }, set: { this.wrappedValue = $0 })
    }

    @MainActor func bindDynamicProperty(to node: Node, key: String) { cell.bind(to: node, key: key) }

    init(key: String, defaultValue: Value, store: UserDefaults?, reader: @escaping (UserDefaults, String) -> Value?, writer: @escaping (UserDefaults, String, Value) -> Void) {
        self.key = key; self.defaultValue = defaultValue; self.store = store ?? .standard; self.reader = reader; self.writer = writer
    }
}

extension AppStorage where Value: AppStorageValue {
    /// Apple: https://developer.apple.com/documentation/swiftui/appstorage/init(wrappedvalue:_:store:)-6ldmk
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        self.init(key: key, defaultValue: wrappedValue, store: store, reader: { Value.read($0, $1) }, writer: { $2.write($0, $1) })
    }
}

extension AppStorage where Value: RawRepresentable, Value.RawValue == String {
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        self.init(key: key, defaultValue: wrappedValue, store: store, reader: { d, k in d.string(forKey: k).flatMap { Value(rawValue: $0) } }, writer: { d, k, v in d.set(v.rawValue, forKey: k) })
    }
}

extension AppStorage where Value: RawRepresentable, Value.RawValue == Int {
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        self.init(key: key, defaultValue: wrappedValue, store: store, reader: { d, k in d.object(forKey: k) == nil ? nil : Value(rawValue: d.integer(forKey: k)) }, writer: { d, k, v in d.set(v.rawValue, forKey: k) })
    }
}

extension AppStorage {
    /// `@AppStorage("k") var v: String? = nil`.
    public init<W: AppStorageValue>(wrappedValue: W?, _ key: String, store: UserDefaults? = nil) where Value == W? {
        self.init(key: key, defaultValue: wrappedValue, store: store, reader: { W.read($0, $1).map { Optional($0) } }, writer: { d, k, v in if let v { v.write(d, k) } else { d.removeObject(forKey: k) } })
    }

    /// An optional value: nil when the key is absent, and assigning nil removes the key.
    public init<W: AppStorageValue>(_ key: String, store: UserDefaults? = nil) where Value == W? {
        self.init(key: key, defaultValue: nil, store: store, reader: { W.read($0, $1).map { Optional($0) } }, writer: { d, k, v in if let v { v.write(d, k) } else { d.removeObject(forKey: k) } })
    }
}
