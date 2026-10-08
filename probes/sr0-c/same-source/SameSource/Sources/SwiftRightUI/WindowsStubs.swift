#if os(Windows)
// SR0-C declaration-only stubs. Mirror the SDK (macOS 27 SwiftUI) shape of the APIs the shared screen uses.
// Bodies trap. This file type-checks shape only; it does not render.
import Foundation

// SDK: `@preconcurrency @_Concurrency::MainActor public protocol View` with
//      `@ContentBuilder @MainActor @preconcurrency var body: Self.Body { get }`
@MainActor @preconcurrency
public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor var body: Body { get }
}

extension Never: View {
    @MainActor public var body: Never { return fatalError() }
}

extension Optional: View where Wrapped: View {
    @MainActor public var body: Never { return fatalError() }
}

public struct EmptyView: View {
    public init() {}
    @MainActor public var body: Never { return fatalError() }
}

public struct TupleView<T>: View {
    @MainActor public var body: Never { return fatalError() }
}

public struct ConditionalContent<TrueContent: View, FalseContent: View>: View {
    @MainActor public var body: Never { return fatalError() }
}

// SDK: `@_functionBuilder public struct ViewBuilder` (result builder)
@resultBuilder
public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { fatalError() }
    public static func buildBlock<each Content: View>(_ content: repeat each Content) -> TupleView<(repeat each Content)> { fatalError() }
    public static func buildExpression<Content: View>(_ content: Content) -> Content { fatalError() }
    public static func buildIf<Content: View>(_ content: Content?) -> Content? { fatalError() }
    public static func buildEither<TrueContent: View, FalseContent: View>(first content: TrueContent) -> ConditionalContent<TrueContent, FalseContent> { fatalError() }
    public static func buildEither<TrueContent: View, FalseContent: View>(second content: FalseContent) -> ConditionalContent<TrueContent, FalseContent> { fatalError() }
}

// SDK: `@frozen @propertyWrapper public struct State<Value> : DynamicProperty`
@propertyWrapper
public struct State<Value> {
    public init(wrappedValue: Value) { fatalError() }
    public var wrappedValue: Value {
        get { fatalError() }
        nonmutating set { fatalError() }
    }
    public var projectedValue: Binding<Value> { fatalError() }
}

// SDK: `@frozen @propertyWrapper @dynamicMemberLookup public struct Binding<Value>`
@dynamicMemberLookup
@propertyWrapper
public struct Binding<Value> {
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) { fatalError() }
    // SDK: `public init(projectedValue: Binding<Value>)` — enables `{ $row in }` closure parameters (SE-0293).
    public init(projectedValue: Binding<Value>) { fatalError() }
    public var wrappedValue: Value {
        get { fatalError() }
        nonmutating set { fatalError() }
    }
    public var projectedValue: Binding<Value> { fatalError() }
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> { fatalError() }
}

// SDK: `extension Binding : RandomAccessCollection where Value : MutableCollection, Value : RandomAccessCollection`
// Each inherited protocol carries the same constraint so the conditional conformances imply one another.
extension Binding: Sequence where Value: MutableCollection, Value: RandomAccessCollection {
    public typealias Element = Binding<Value.Element>
    public func makeIterator() -> AnyIterator<Binding<Value.Element>> { fatalError() }
}

extension Binding: Collection where Value: MutableCollection, Value: RandomAccessCollection {
    public typealias Index = Value.Index
    public var startIndex: Value.Index { fatalError() }
    public var endIndex: Value.Index { fatalError() }
    public subscript(position: Value.Index) -> Binding<Value.Element> { fatalError() }
    public func index(after i: Value.Index) -> Value.Index { fatalError() }
}

extension Binding: BidirectionalCollection where Value: MutableCollection, Value: RandomAccessCollection {
    public func index(before i: Value.Index) -> Value.Index { fatalError() }
}

extension Binding: RandomAccessCollection where Value: MutableCollection, Value: RandomAccessCollection {}

// SDK: `extension Binding : Identifiable where Value : Identifiable`
extension Binding: Identifiable where Value: Identifiable {
    public var id: Value.ID { fatalError() }
}

// SDK: `@dynamicMemberLookup @propertyWrapper public struct Bindable<Value>`
@dynamicMemberLookup
@propertyWrapper
public struct Bindable<Value> {
    public init(wrappedValue: Value) { fatalError() }
    public var wrappedValue: Value { fatalError() }
    public var projectedValue: Bindable<Value> { fatalError() }
    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> { fatalError() }
}

// SDK: `@frozen @propertyWrapper public struct Environment<Value>`
@propertyWrapper
public struct Environment<Value> {
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { fatalError() }
    public var wrappedValue: Value { fatalError() }
}

public struct EnvironmentValues {
    public var colorScheme: ColorScheme { fatalError() }
}

public enum ColorScheme: Hashable, Sendable {
    case light
    case dark
}

// SDK: `@frozen @propertyWrapper public struct FocusState<Value> where Value : Hashable`
@propertyWrapper
public struct FocusState<Value: Hashable> {
    public init() where Value: ExpressibleByNilLiteral { fatalError() }
    public var wrappedValue: Value {
        get { fatalError() }
        nonmutating set { fatalError() }
    }
    public var projectedValue: FocusState<Value>.Binding { fatalError() }

    public struct Binding {}
}

extension View {
    // SDK: `nonisolated public func focused<Value>(_ binding: FocusState<Value>.Binding, equals value: Value) -> some View where Value : Hashable`
    public func focused<Value: Hashable>(_ binding: FocusState<Value>.Binding, equals value: Value) -> some View {
        fatalError()
    }

    // SDK: `nonisolated public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View`
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        fatalError()
    }

    // SDK: `nonisolated public func onAppear(perform action: (() -> Void)? = nil) -> some View`
    public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        fatalError()
    }

    // SDK: `nonisolated public func animation<V>(_ animation: Animation?, value: V) -> some View where V : Equatable`
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        fatalError()
    }

    // SDK: `nonisolated public func task(name:priority:file:line:_ action: sending @escaping @isolated(any) () async -> Void) -> some View`
    public func task(
        name: String? = nil,
        priority: TaskPriority = .userInitiated,
        @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void
    ) -> some View {
        fatalError()
    }
}

public struct Edge: Sendable {
    public struct Set: Sendable {
        public static let all = Set()
        public init() {}
    }
}

public struct Animation: Sendable {
    public static let `default` = Animation()
    public init() {}
}

// SDK: `public struct Text` (LocalizedStringKey in SDK; String here for shape checking)
public struct Text: View {
    public init(_ content: String) { fatalError() }
    @MainActor public var body: Never { return fatalError() }
}

public struct Spacer: View {
    public init(minLength: CGFloat? = nil) { fatalError() }
    @MainActor public var body: Never { return fatalError() }
}

// SDK: `nonisolated public struct Button<Label> : View where Label : View`
public struct Button<Label: View>: View {
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) { fatalError() }
    @MainActor public var body: Never { return fatalError() }
}

extension Button where Label == Text {
    public init(_ titleKey: String, action: @escaping () -> Void) { fatalError() }
}

// SDK: `nonisolated public struct TextField<Label> : View where Label : View`
public struct TextField<Label: View>: View {
    public init(text: Binding<String>, @ViewBuilder label: () -> Label) { fatalError() }
    @MainActor public var body: Never { return fatalError() }
}

extension TextField where Label == Text {
    public init(_ titleKey: String, text: Binding<String>) { fatalError() }
}

// SDK: `nonisolated public struct Toggle<Label> : View where Label : View`
public struct Toggle<Label: View>: View {
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) { fatalError() }
    @MainActor public var body: Never { return fatalError() }
}

extension Toggle where Label == Text {
    public init(_ titleKey: String, isOn: Binding<Bool>) { fatalError() }
}

public struct HorizontalAlignment: Sendable {
    public static let leading = HorizontalAlignment()
    public static let center = HorizontalAlignment()
    public static let trailing = HorizontalAlignment()
}

public struct VerticalAlignment: Sendable {
    public static let top = VerticalAlignment()
    public static let center = VerticalAlignment()
    public static let bottom = VerticalAlignment()
}

// SDK: `public struct VStack<Content> : View where Content : View`
public struct VStack<Content: View>: View {
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) { fatalError() }
    @MainActor public var body: Never { return fatalError() }
}

public struct HStack<Content: View>: View {
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) { fatalError() }
    @MainActor public var body: Never { return fatalError() }
}

// SDK: `nonisolated public struct List<SelectionValue, Content> : View where SelectionValue : Hashable, Content : View`
public struct List<SelectionValue: Hashable, Content: View>: View {
    @MainActor public var body: Never { return fatalError() }
}

extension List where SelectionValue == Never {
    public init(@ViewBuilder content: () -> Content) { fatalError() }
}

// SDK: `public protocol DynamicViewContent : View`
public protocol DynamicViewContent: View {}

// SDK: `public struct ForEach<Data, ID, Content>`
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: DynamicViewContent {
    @MainActor public var body: Never { return fatalError() }
}

extension ForEach where ID == Data.Element.ID, Data.Element: Identifiable {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) { fatalError() }
}

// SDK: `@_disfavoredOverload public init<C>(_ data: Binding<C>, @ContentBuilder content: @escaping (Binding<C.Element>) -> Content) where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, ID == C.Element.ID, C: MutableCollection, C: RandomAccessCollection`
// The closure parameter is typed Binding<C.Element>, which is what makes `{ $row in ... }` a valid projection parameter.
extension ForEach {
    @_disfavoredOverload
    public init<C>(_ data: Binding<C>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content)
    where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, ID == C.Element.ID, C: MutableCollection, C: RandomAccessCollection, C.Element: Identifiable
    {
        fatalError()
    }
}

extension DynamicViewContent {
    // SDK: `nonisolated public func onMove(perform action: ((IndexSet, Int) -> Void)?) -> some DynamicViewContent`
    public func onMove(perform action: ((IndexSet, Int) -> Void)?) -> some DynamicViewContent {
        DynamicViewStub()
    }
}

public struct DynamicViewStub: DynamicViewContent {
    public init() {}
    @MainActor public var body: Never { return fatalError() }
}

// Not in SDK SwiftUI symbol set under this name; the screen uses SwiftUI's `move(fromOffsets:toOffset:)`.
// On macOS that comes from SwiftUI (not Foundation). Windows must supply it here.
extension MutableCollection {
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) { fatalError() }
}

// SDK: `@frozen public struct ProposedViewSize : Equatable`
public struct ProposedViewSize: Equatable {
    public var width: CGFloat?
    public var height: CGFloat?
    public init(width: CGFloat?, height: CGFloat?) { self.width = width; self.height = height }
    public static var zero: ProposedViewSize { ProposedViewSize(width: 0, height: 0) }
    public static var unspecified: ProposedViewSize { ProposedViewSize(width: nil, height: nil) }
    public static var infinity: ProposedViewSize { ProposedViewSize(width: .infinity, height: .infinity) }
}

// SDK: `@frozen public struct UnitPoint : Hashable`
public struct UnitPoint: Hashable, Sendable {
    public static let topLeading = UnitPoint()
    public init() {}
}

// SDK: `public struct LayoutSubview : Equatable`
public struct LayoutSubview: Equatable {
    public static func == (a: LayoutSubview, b: LayoutSubview) -> Bool { fatalError() }
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { fatalError() }
    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) { fatalError() }
}

// SDK: `public struct LayoutSubviews : Equatable, RandomAccessCollection, Sendable`
public struct LayoutSubviews: Equatable, RandomAccessCollection, Sendable {
    public typealias Element = LayoutSubview
    public typealias Index = Int
    public var startIndex: Int { fatalError() }
    public var endIndex: Int { fatalError() }
    public subscript(position: Int) -> LayoutSubview { fatalError() }
    public func index(after i: Int) -> Int { fatalError() }
    public func index(before i: Int) -> Int { fatalError() }
    public static func == (a: LayoutSubviews, b: LayoutSubviews) -> Bool { fatalError() }
}

// SDK: `@preconcurrency public protocol Layout : Sendable, Animatable`
// Deviation: Animatable is omitted (the screen does not use it).
@preconcurrency
public protocol Layout: Sendable {
    associatedtype Cache = Void
    typealias Subviews = LayoutSubviews
    func makeCache(subviews: Subviews) -> Cache
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
}

extension Layout where Cache == Void {
    public func makeCache(subviews: Subviews) -> Void { fatalError() }
}

extension Layout {
    // SDK: `callAsFunction<V>(@ContentBuilder _ content: () -> V) -> some View where V : View`
    public func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        fatalError()
    }
}

#endif
