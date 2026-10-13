import Foundation
import Observation

// Dynamic properties are value-type wrappers that hold a reference cell. The graph binds each
// cell to the owning node (by property label) before evaluating that node's body, so storage
// lives with node identity and survives re-evaluation of the view value.

/// Observable storage for one property of one node. Reads inside a body register observation
/// dependencies; writes notify the graph through the observation onChange path.
@Observable
@MainActor
final class StateBox<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor
protocol DynamicPropertyStorage {
    func bindDynamicProperty(to node: Node, key: String)
}

@MainActor
final class StateCell<Value> {
    let initial: Value
    private var box: StateBox<Value>?

    init(_ initial: Value) { self.initial = initial }

    func bind(to node: Node, key: String) {
        if let existing = node.storage[key] as? StateBox<Value> {
            box = existing
            return
        }
        let fresh = StateBox(initial)
        node.storage[key] = fresh
        box = fresh
    }

    /// Storage used when the view is read outside a graph (for example in a unit test).
    var resolved: StateBox<Value> {
        if let box { return box }
        let fresh = StateBox(initial)
        box = fresh
        return fresh
    }
}

// MARK: - State

@propertyWrapper
public struct State<Value>: DynamicPropertyStorage {
    let cell: StateCell<Value>

    public init(wrappedValue: Value) { cell = StateCell(wrappedValue) }

    @MainActor
    public var wrappedValue: Value {
        get { cell.resolved.value }
        nonmutating set { cell.resolved.value = newValue }
    }

    @MainActor
    public var projectedValue: Binding<Value> {
        let cell = cell
        return Binding(get: { cell.resolved.value }, set: { cell.resolved.value = $0 })
    }

    @MainActor
    func bindDynamicProperty(to node: Node, key: String) {
        cell.bind(to: node, key: key)
    }
}

// MARK: - Binding

/// SwiftUI `Transaction`: the animation context a binding setter receives. A binding hands its setter the transaction it carries
/// (empty unless `.transaction(_:)` or `.animation(_:)` set one), NOT the ambient `withAnimation` transaction (macOS oracle, SR1
/// lane B block 12: setter calls inside `withAnimation(.easeIn)` and `withTransaction` still saw a nil animation).
public struct Transaction: Sendable, Equatable {
    public var animation: Animation?
    public var disablesAnimations: Bool

    public init() {
        animation = nil
        disablesAnimations = false
    }

    public init(animation: Animation?) {
        self.animation = animation
        disablesAnimations = false
    }
}

@MainActor
@dynamicMemberLookup
@propertyWrapper
public struct Binding<Value> {
    private let getter: () -> Value
    private let setter: (Value, Transaction) -> Void
    private let carried: Transaction

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        getter = get
        setter = { value, _ in set(value) }
        carried = Transaction()
    }

    /// Setter that also receives the binding's transaction (empty unless `.transaction(_:)` / `.animation(_:)` set one).
    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
        getter = get
        setter = set
        carried = Transaction()
    }

    private init(getter: @escaping () -> Value, setter: @escaping (Value, Transaction) -> Void, carried: Transaction) {
        self.getter = getter
        self.setter = setter
        self.carried = carried
    }

    /// A binding that always reads `value` and ignores writes.
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    /// The binding with `transaction` as the one its setter receives (replaces, does not merge: oracle).
    public func transaction(_ transaction: Transaction) -> Binding<Value> {
        Binding(getter: getter, setter: setter, carried: transaction)
    }

    /// The binding whose setter receives `animation` (default `.default`): `transaction(Transaction(animation:))`.
    public func animation(_ animation: Animation? = .default) -> Binding<Value> {
        transaction(Transaction(animation: animation))
    }

    public init(projectedValue: Binding<Value>) {
        self = projectedValue
    }

    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue, carried) }
    }

    public var projectedValue: Binding<Value> { self }

    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        let get = getter
        let set = setter
        return Binding<Subject>(
            getter: { get()[keyPath: keyPath] },
            setter: { newValue, transaction in
                var whole = get()
                whole[keyPath: keyPath] = newValue
                set(whole, transaction)
            },
            carried: carried
        )
    }
}

extension Binding: @MainActor Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

// As in SwiftUI, a binding to a collection is itself a collection of bindings. Each element binding
// addresses its element by index on access. `ForEach($items)` prefers the id-keyed initializers above.
extension Binding: @MainActor Sequence, @MainActor Collection, @MainActor BidirectionalCollection,
    @MainActor RandomAccessCollection, @MainActor MutableCollection
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

// MARK: - Bindable

@MainActor
@dynamicMemberLookup
@propertyWrapper
public struct Bindable<Value: AnyObject> {
    public let wrappedValue: Value

    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }

    public var projectedValue: Bindable<Value> { self }

    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> {
        let object = wrappedValue
        return Binding<Subject>(
            get: { object[keyPath: keyPath] },
            set: { object[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - Environment

public enum ColorScheme: Hashable, Sendable {
    case light
    case dark
}

/// Layout direction. Under `.rightToLeft` the runtime mirrors each child's frame within its container's
/// bounds after the container computes positions left-to-right (SwiftUI semantics); text glyph order and
/// image content are not mirrored by layout.
public enum LayoutDirection: Hashable, Sendable {
    case leftToRight
    case rightToLeft
}

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

private enum ColorSchemeKey: EnvironmentKey {
    static var defaultValue: ColorScheme { .light }
}

public struct EnvironmentValues {
    private var storage: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get { (storage[ObjectIdentifier(key)] as? K.Value) ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }

    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }

    public var layoutDirection: LayoutDirection {
        get { self[LayoutDirectionKey.self] }
        set { self[LayoutDirectionKey.self] = newValue }
    }

    /// Display scale used by image & provider consumers. Headless runtime defaults to one;
    /// host may provide its actual backing scale through environment.
    /// Apple: https://developer.apple.com/documentation/swiftui/environmentvalues/displayscale
    public var displayScale: CGFloat {
        get { self[DisplayScaleKey.self] }
        set { self[DisplayScaleKey.self] = newValue }
    }

    /// Animations jump to their final values and still deliver completions. Tests set it directly; a
    /// host feeds an explicit app or test override through `Graph.setRootEnvironment`. A Windows host does not map the OS
    /// "Animation effects" setting here (decision 2026-10-10: animations must work with the OS setting off); macOS supplies its own.
    public var accessibilityReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }

    /// True when labels of labeled controls are removed from resolved layout content.
    public var labelsHidden: Bool {
        get { self[LabelsHiddenKey.self] }
        set { self[LabelsHiddenKey.self] = newValue }
    }

    var toggleStyleMetadata: String? {
        get { self[ToggleStyleMetadataKey.self] }
        set { self[ToggleStyleMetadataKey.self] = newValue }
    }
}

private enum LayoutDirectionKey: EnvironmentKey {
    static var defaultValue: LayoutDirection { .leftToRight }
}

private enum DisplayScaleKey: EnvironmentKey {
    static var defaultValue: CGFloat { 1 }
}

private enum ReduceMotionKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

private enum LabelsHiddenKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

private enum ToggleStyleMetadataKey: EnvironmentKey {
    static var defaultValue: String? { nil }
}

@MainActor
final class EnvironmentCell {
    weak var node: Node?
}

@propertyWrapper
public struct Environment<Value>: DynamicPropertyStorage {
    let keyPath: KeyPath<EnvironmentValues, Value>
    let cell = EnvironmentCell()

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { self.keyPath = keyPath }

    @MainActor
    public var wrappedValue: Value {
        let environment = cell.node?.environment ?? EnvironmentValues()
        return environment[keyPath: keyPath]
    }

    @MainActor
    func bindDynamicProperty(to node: Node, key: String) {
        cell.node = node
    }
}

// MARK: - FocusState

@propertyWrapper
public struct FocusState<Value: Hashable>: DynamicPropertyStorage {
    let cell: StateCell<Value>

    public init() where Value: ExpressibleByNilLiteral {
        cell = StateCell(Value(nilLiteral: ()))
    }

    @MainActor
    public var wrappedValue: Value {
        get { cell.resolved.value }
        nonmutating set { cell.resolved.value = newValue }
    }

    @MainActor
    public var projectedValue: FocusState<Value>.Binding {
        FocusState<Value>.Binding(cell: cell)
    }

    @MainActor
    func bindDynamicProperty(to node: Node, key: String) {
        cell.bind(to: node, key: key)
    }

    public struct Binding {
        let cell: StateCell<Value>
        @MainActor
        public var wrappedValue: Value {
            get { cell.resolved.value }
            nonmutating set { cell.resolved.value = newValue }
        }

        /// Makes `value` the focus.
        @MainActor
        func assign(_ value: Value) {
            cell.resolved.value = value
        }

        /// Returns the focus to its default (nil for the `init()` form), as when the focused view is removed.
        @MainActor
        func reset() {
            cell.resolved.value = cell.initial
        }
    }
}
