import Foundation

// SR0-S fresh runtime: SwiftUI programming-model semantics without any renderer.
// Public signatures mirror probes/sr0-c/.../WindowsStubs.swift.

// MARK: - View protocol

@MainActor @preconcurrency
public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor var body: Body { get }
}

extension View {
    /// Evaluates `body` through an existential so the graph can expand the result.
    @MainActor
    func evaluateBody() -> any View { body }
}

extension Never: View {
    @MainActor public var body: Never { return fatalError("Never has no body") }
}

public struct EmptyView: View {
    public init() {}
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
}

/// Views that only group children. Their children are spliced into the parent
/// with structural segments; they never become graph nodes themselves.
@MainActor
protocol ViewContainer {
    func parts() -> [(Segment, any View)]
}

/// Views that become graph nodes without a user `body`.
@MainActor
protocol PrimitiveView {
    var nodeKind: NodeKind { get }
    var nodeContent: (any View)? { get }
}

// MARK: - Builder containers

@MainActor
public struct TupleView<T>: View {
    public let value: T
    /// The tuple's views in order, listed when the builder made the tuple (no reflection needed to read them back).
    let listed: [any View]?
    public init(_ value: T) {
        self.value = value
        listed = nil
    }
    init(value: T, listed: [any View]) {
        self.value = value
        self.listed = listed
    }
    @MainActor public var body: Never { return fatalError("TupleView has no body") }
}

extension TupleView: ViewContainer {
    @MainActor
    func parts() -> [(Segment, any View)] {
        if let listed {
            var out: [(Segment, any View)] = []
            out.reserveCapacity(listed.count)
            for (index, view) in listed.enumerated() { out.append((.index(index), view)) }
            return out
        }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .tuple {
            var out: [(Segment, any View)] = []
            for (index, child) in mirror.children.enumerated() {
                if let view = child.value as? any View { out.append((.index(index), view)) }
            }
            return out
        }
        if let view = value as? any View { return [(.index(0), view)] }
        return []
    }
}

@MainActor
public struct ConditionalContent<TrueContent: View, FalseContent: View>: View {
    let first: TrueContent?
    let second: FalseContent?
    init(first: TrueContent?, second: FalseContent?) {
        self.first = first
        self.second = second
    }
    @MainActor public var body: Never { return fatalError("ConditionalContent has no body") }
}

extension ConditionalContent: ViewContainer {
    @MainActor
    func parts() -> [(Segment, any View)] {
        if let first { return [(.branch(0), first)] }
        if let second { return [(.branch(1), second)] }
        return []
    }
}

@MainActor
@resultBuilder
public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<each Content: View>(_ content: repeat each Content) -> TupleView<(repeat each Content)> {
        var listed: [any View] = []
        for view in repeat each content { listed.append(view) }
        return TupleView(value: (repeat each content), listed: listed)
    }
    public static func buildExpression<Content: View>(_ content: Content) -> Content { content }
    public static func buildIf<Content: View>(_ content: Content?) -> Content? { content }
    public static func buildEither<TrueContent: View, FalseContent: View>(first content: TrueContent) -> ConditionalContent<TrueContent, FalseContent> {
        ConditionalContent(first: content, second: nil)
    }
    public static func buildEither<TrueContent: View, FalseContent: View>(second content: FalseContent) -> ConditionalContent<TrueContent, FalseContent> {
        ConditionalContent(first: nil, second: content)
    }
}

extension Optional: View where Wrapped: View {
    @MainActor public var body: Never { return fatalError("Optional has no body") }
}

// MARK: - Primitives

public struct Text: View, PrimitiveView {
    let string: String
    public init(_ content: String) { string = content }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .text(string) }
    var nodeContent: (any View)? { nil }
}

public struct Spacer: View, PrimitiveView {
    let minLength: CGFloat
    public init(minLength: CGFloat? = nil) { self.minLength = minLength ?? 0 }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .spacer(minLength) }
    var nodeContent: (any View)? { nil }
}

/// Semantic role of a button in an alert or dialog. Apple: https://developer.apple.com/documentation/swiftui/buttonrole
public enum ButtonRole: Hashable, Sendable {
    case cancel
    case destructive
}

public struct Button<Label: View>: View, PrimitiveView {
    let action: () -> Void
    let label: Label
    let role: ButtonRole?
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
        self.role = nil
    }
    /// Apple: https://developer.apple.com/documentation/swiftui/button/init(role:action:label:)
    public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
        self.role = role
    }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .button(action) }
    var nodeContent: (any View)? { label }
}

extension Button where Label == Text {
    public init(_ titleKey: String, action: @escaping () -> Void) {
        let label: () -> Text = { Text(titleKey) }
        self.init(action: action, label: label)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/button/init(_:role:action:)
    public init(_ titleKey: String, role: ButtonRole?, action: @escaping () -> Void) {
        let label: () -> Text = { Text(titleKey) }
        self.init(role: role, action: action, label: label)
    }
}

public struct TextField<Label: View>: View, PrimitiveView {
    let text: Binding<String>
    let label: Label
    public init(text: Binding<String>, @ViewBuilder label: () -> Label) {
        self.text = text
        self.label = label()
    }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .textField(text) }
    var nodeContent: (any View)? { nil }
}

extension TextField where Label == Text {
    public init(_ titleKey: String, text: Binding<String>) {
        let label: () -> Text = { Text(titleKey) }
        self.init(text: text, label: label)
    }
}

// MARK: - Alignment

public struct HorizontalAlignment: Sendable, Equatable {
    enum Kind: Sendable { case leading, center, trailing }
    let kind: Kind

    public static let leading = HorizontalAlignment(kind: .leading)
    public static let center = HorizontalAlignment(kind: .center)
    public static let trailing = HorizontalAlignment(kind: .trailing)

    var crossAlignment: CrossAlignment {
        switch kind {
        case .leading: return .start
        case .center: return .middle
        case .trailing: return .end
        }
    }
}

public struct VerticalAlignment: Sendable, Equatable {
    enum Kind: Sendable { case top, center, bottom }
    let kind: Kind

    public static let top = VerticalAlignment(kind: .top)
    public static let center = VerticalAlignment(kind: .center)
    public static let bottom = VerticalAlignment(kind: .bottom)

    var crossAlignment: CrossAlignment {
        switch kind {
        case .top: return .start
        case .center: return .middle
        case .bottom: return .end
        }
    }
}

// MARK: - Stacks

public struct VStack<Content: View>: View, PrimitiveView {
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind {
        .stack(StackSpec(name: "VStack", axis: .vertical, cross: alignment.crossAlignment,
                         spacing: spacing ?? defaultStackSpacing, fillsCross: false))
    }
    var nodeContent: (any View)? { content }
}

public struct HStack<Content: View>: View, PrimitiveView {
    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind {
        .stack(StackSpec(name: "HStack", axis: .horizontal, cross: alignment.crossAlignment,
                         spacing: spacing ?? defaultStackSpacing, fillsCross: false))
    }
    var nodeContent: (any View)? { content }
}

/// Vertical stack that realizes every row (no virtualization yet). Like VStack, a reinserted row's
/// `@State` resets (SR0-O F3: macOS 27 LazyVStack in a ScrollView resets it, unlike List).
public struct LazyVStack<Content: View>: View, PrimitiveView {
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind {
        .stack(StackSpec(name: "LazyVStack", axis: .vertical, cross: alignment.crossAlignment,
                         spacing: spacing ?? defaultStackSpacing, fillsCross: false))
    }
    var nodeContent: (any View)? { content }
}

/// Vertical scroll container. It takes the proposed size, lays its content out unbounded in height, and
/// offsets the content by the scroll offset (see `Graph.scroll(_:to:)`). Horizontal scrolling is not modeled.
public struct ScrollView<Content: View>: View, PrimitiveView {
    let content: Content
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .scroll }
    var nodeContent: (any View)? { content }
}

/// Apple: https://developer.apple.com/documentation/swiftui/list
public struct List<SelectionValue: Hashable, Content: View>: View, PrimitiveView {
    let content: Content
    /// Selection binding, nil for an unselectable list. Set by `init(selection:content:)` (Selection.swift).
    let selectionAccess: SelectionAccess?
    init(content: Content, selectionAccess: SelectionAccess? = nil) {
        self.content = content
        self.selectionAccess = selectionAccess
    }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    /// Rows stack vertically with no gap and take the full proposed width.
    var nodeKind: NodeKind {
        .stack(StackSpec(name: "List", axis: .vertical, cross: .start, spacing: 0, fillsCross: true,
                         retainsRemovedRowState: true))
    }
    var nodeContent: (any View)? { content }
}

extension List where SelectionValue == Never {
    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content())
    }
}

// MARK: - Dynamic content and ForEach

public protocol DynamicViewContent: View {}

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: DynamicViewContent, ViewContainer {
    let items: Data
    let idOf: (Data.Element) -> ID
    let makeContent: (Data.Element) -> Content

    init(items: Data, idOf: @escaping (Data.Element) -> ID, makeContent: @escaping (Data.Element) -> Content) {
        self.items = items
        self.idOf = idOf
        self.makeContent = makeContent
    }

    /// Disfavored so that `ForEach($items)` over a Binding selects the id-keyed binding initializer.
    @_disfavoredOverload
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(items: data, idOf: { $0[keyPath: id] }, makeContent: content)
    }

    @MainActor public var body: Never { return fatalError("ForEach has no body") }

    @MainActor
    func parts() -> [(Segment, any View)] {
        items.map { element in
            (Segment.keyed(AnyHashable(idOf(element))), makeContent(element) as any View)
        }
    }
}

extension ForEach where ID == Data.Element.ID, Data.Element: Identifiable {
    @_disfavoredOverload
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach {
    /// `ForEach($items) { $item in ... }`. Identity comes from each element's `id`. Each row binding
    /// resolves its element by that id when it is read or written, so a row handle never targets a
    /// stale index after inserts, deletes or moves.
    public init<C: MutableCollection & RandomAccessCollection>(
        _ data: Binding<C>,
        @ViewBuilder content: @escaping (Binding<C.Element>) -> Content
    ) where C.Element: Identifiable, ID == C.Element.ID, Data == LazyMapSequence<C.Indices, (C.Index, ID)> {
        self.init(bindingRows: data, key: { $0.id }, content: content)
    }

    /// `ForEach($items, id: \.key) { $item in ... }`: identity comes from the key path.
    public init<C: MutableCollection & RandomAccessCollection>(
        _ data: Binding<C>,
        id: KeyPath<C.Element, ID>,
        @ViewBuilder content: @escaping (Binding<C.Element>) -> Content
    ) where Data == LazyMapSequence<C.Indices, (C.Index, ID)> {
        self.init(bindingRows: data, key: { $0[keyPath: id] }, content: content)
    }

    private init<C: MutableCollection & RandomAccessCollection>(
        bindingRows data: Binding<C>,
        key: @escaping (C.Element) -> ID,
        content: @escaping (Binding<C.Element>) -> Content
    ) where Data == LazyMapSequence<C.Indices, (C.Index, ID)> {
        let snapshot = data.wrappedValue
        let pairs: LazyMapSequence<C.Indices, (C.Index, ID)> = snapshot.indices.lazy.map { index in
            (index, key(snapshot[index]))
        }
        self.init(
            items: pairs,
            idOf: { $0.1 },
            makeContent: { pair in
                let id = pair.1
                let hint = pair.0
                let fallback = snapshot[hint]
                // The element is found by id, so a row handle never targets a stale index. The index it had at evaluation is
                // tried first (one comparison); only a row that has moved since needs the scan.
                @MainActor func locate(_ current: C) -> C.Index? {
                    if hint >= current.startIndex, hint < current.endIndex, key(current[hint]) == id { return hint }
                    return current.firstIndex(where: { key($0) == id })
                }
                let row = Binding<C.Element>(
                    get: {
                        let current = data.wrappedValue
                        return locate(current).map { current[$0] } ?? fallback
                    },
                    set: { newValue in
                        var current = data.wrappedValue
                        guard let index = locate(current) else { return }
                        current[index] = newValue
                        data.wrappedValue = current
                    }
                )
                return content(row)
            }
        )
    }
}

extension DynamicViewContent {
    /// Accepted for API shape. Move gestures are not wired on the headless runtime; tests drive
    /// `MutableCollection.move(fromOffsets:toOffset:)` on the model directly.
    public func onMove(perform action: ((IndexSet, Int) -> Void)?) -> some DynamicViewContent {
        OnMoveContent(content: self, handler: action)
    }
}

struct OnMoveContent<Content: DynamicViewContent>: DynamicViewContent, ViewContainer {
    let content: Content
    let handler: ((IndexSet, Int) -> Void)?
    @MainActor public var body: Never { return fatalError("OnMoveContent has no body") }
    @MainActor
    func parts() -> [(Segment, any View)] {
        (content as? ViewContainer)?.parts() ?? []
    }
}

extension MutableCollection where Self: RandomAccessCollection {
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var items = Array(self)
        let moving = source.map { items[$0] }
        var target = destination
        for index in source.reversed() {
            items.remove(at: index)
            if index < target { target -= 1 }
        }
        items.insert(contentsOf: moving, at: target)
        for (offset, element) in items.enumerated() {
            self[self.index(startIndex, offsetBy: offset)] = element
        }
    }
}

public struct Edge: Sendable {
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1 << 0)
        public static let leading = Set(rawValue: 1 << 1)
        public static let bottom = Set(rawValue: 1 << 2)
        public static let trailing = Set(rawValue: 1 << 3)
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public static let all: Set = [.top, .leading, .bottom, .trailing]
    }
}
