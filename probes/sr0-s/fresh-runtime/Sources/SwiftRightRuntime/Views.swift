import Foundation
import Observation

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
    /// True when this container's parts are the same views every time the owner re-expands it without its own view
    /// having been replaced (only the data behind a keyed `ForEach` may differ, and its rows track that themselves). The
    /// graph then re-reconciles such an owner without re-evaluating the unchanged rows beneath it. A container that
    /// wraps its rows with position-dependent state (`onDelete`) says false.
    var supportsRefreshSkip: Bool { get }
}

extension ViewContainer {
    var supportsRefreshSkip: Bool { false }
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
    var supportsRefreshSkip: Bool { true }

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
    var supportsRefreshSkip: Bool { true }

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
    /// One child is returned as it is (SwiftUI's `buildBlock(_:)`), so `Trailing == HubNoTrailing` holds for `{ HubNoTrailing() }`.
    public static func buildBlock<Content: View>(_ content: Content) -> Content { content }
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
    /// Text that is shown as written (no localisation lookup; the runtime has none, so it equals `init(_:)`).
    /// Apple: https://developer.apple.com/documentation/swiftui/text/init(verbatim:)
    public init(verbatim content: String) { string = content }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { .text(string) }
    var nodeContent: (any View)? { nil }

    /// Apple: https://developer.apple.com/documentation/swiftui/text/case
    public enum Case: Hashable, Sendable {
        case uppercase, lowercase
        func apply(_ string: String) -> String { self == .uppercase ? string.uppercased() : string.lowercased() }
    }
}

public struct Spacer: View, PrimitiveView {
    let minLength: CGFloat
    /// A nil `minLength` is 8 pt on macOS, in every stack and whatever the stack's own spacing is (measured on macOS 27: `HStack(spacing: 0) { 40 pt; Spacer(); 40 pt }` in
    /// an 80 pt frame still leaves an 8 pt gap, and so does a VStack; `Spacer(minLength: 0)` collapses to nothing).
    public init(minLength: CGFloat? = nil) { self.minLength = minLength ?? 8 }
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
    /// The placeholder text when it differs from the title (`prompt:`).
    let prompt: Text?
    public init(text: Binding<String>, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
        self.text = text
        self.prompt = prompt
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

    /// A field whose text may wrap over several lines (`axis: .vertical`). Round 5 (hub gap G17): the field is accepted and draws, edits and sizes as the single-line field; the growth
    /// to several lines (up to `lineLimit`) and the wrapping of long text are not delivered (docs/sr1-decisions.md F7). An empty or short field is the same on macOS (measured).
    /// Apple: https://developer.apple.com/documentation/swiftui/textfield/init(_:text:axis:)
    public init(_ titleKey: String, text: Binding<String>, axis: Axis) {
        let label: () -> Text = { Text(titleKey) }
        self.init(text: text, label: label)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/textfield/init(_:text:prompt:axis:)
    public init(_ titleKey: String, text: Binding<String>, prompt: Text?, axis: Axis) {
        let label: () -> Text = { Text(titleKey) }
        self.init(text: text, prompt: prompt, label: label)
    }

    /// The placeholder is `prompt` when given, else the title (macOS: both draw the grey placeholder).
    /// Apple: https://developer.apple.com/documentation/swiftui/textfield/init(_:text:prompt:)
    public init(_ titleKey: String, text: Binding<String>, prompt: Text?) {
        let label: () -> Text = { Text(titleKey) }
        self.init(text: text, prompt: prompt, label: label)
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
    enum Kind: Sendable { case top, center, bottom, firstTextBaseline, lastTextBaseline }
    let kind: Kind

    public static let top = VerticalAlignment(kind: .top)
    public static let center = VerticalAlignment(kind: .center)
    public static let bottom = VerticalAlignment(kind: .bottom)
    /// Aligns the first line's baseline of each child of an `HStack` (a child with no text counts its bottom edge). Elsewhere (a ZStack, a frame) it centres.
    /// Apple: https://developer.apple.com/documentation/swiftui/verticalalignment/firsttextbaseline
    public static let firstTextBaseline = VerticalAlignment(kind: .firstTextBaseline)
    public static let lastTextBaseline = VerticalAlignment(kind: .lastTextBaseline)

    var crossAlignment: CrossAlignment {
        switch kind {
        case .top: return .start
        case .center: return .middle
        case .bottom: return .end
        case .firstTextBaseline: return .firstBaseline
        case .lastTextBaseline: return .lastBaseline
        }
    }
}

// MARK: - Overlay

struct OverlayStack<Base: View, Overlay: View>: View, PrimitiveView {
    let base: Base
    let overlay: Overlay
    let alignment: Alignment

    @MainActor public var body: Never { return fatalError("overlay has no body") }
    var nodeKind: NodeKind {
        .stack(StackSpec(name: "Overlay", axis: .overlay, cross: .middle, alignment: alignment, spacing: 0, fillsCross: false))
    }
    var nodeContent: (any View)? {
        TupleView<(Base, Overlay)>(value: (base, overlay), listed: [base, overlay])
    }
}

extension View {
    /// Draws overlay content above this view; base view determines measured size.
    public func overlay<Overlay: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Overlay
    ) -> some View {
        OverlayStack(base: self, overlay: content(), alignment: alignment)
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
        { var spec = StackSpec(name: "VStack", axis: .vertical, cross: alignment.crossAlignment,
                         spacing: spacing ?? defaultStackSpacing, fillsCross: false); spec.spacingIsDefault = spacing == nil; return .stack(spec) }()
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
        { var spec = StackSpec(name: "HStack", axis: .horizontal, cross: alignment.crossAlignment,
                         spacing: spacing ?? defaultStackSpacing, fillsCross: false); spec.spacingIsDefault = spacing == nil; return .stack(spec) }()
    }
    var nodeContent: (any View)? { content }
}

/// Overlapping stack whose children keep declaration order for painting and hit testing.
public struct ZStack<Content: View>: View, PrimitiveView {
    let alignment: Alignment
    let content: Content
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind {
        .stack(StackSpec(name: "ZStack", axis: .overlap, cross: .middle, alignment: alignment, spacing: 0, fillsCross: false))
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
        { var spec = StackSpec(name: "LazyVStack", axis: .vertical, cross: alignment.crossAlignment,
                         spacing: spacing ?? defaultStackSpacing, fillsCross: false); spec.spacingIsDefault = spacing == nil; return .stack(spec) }()
    }
    var nodeContent: (any View)? { content }
}

/// Scroll container. The content-only initializer preserves the legacy vertical behavior.
public struct ScrollView<Content: View>: View, PrimitiveView {
    let content: Content
    let configuration: ScrollViewConfiguration?
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.configuration = nil
    }
    @MainActor public var body: Never { return fatalError("primitive view has no body") }
    var nodeKind: NodeKind { configuration.map(NodeKind.scrollView) ?? .scroll }
    var nodeContent: (any View)? { content }
}

extension ScrollView {
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.configuration = ScrollViewConfiguration(axes: axes, showsIndicators: showsIndicators)
    }
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
    /// Builds the keyed row views. For a ForEach over a binding it reads the data when called (see `ExpansionContext`),
    /// not when the ForEach is built, so the node that expands it, not the body that wrote it, depends on the data.
    let makeParts: @MainActor () -> [(Segment, any View)]

    init(items: Data, idOf: @escaping (Data.Element) -> ID, makeContent: @escaping (Data.Element) -> Content) {
        makeParts = {
            items.map { element in
                (Segment.keyed(AnyHashable(idOf(element))), makeContent(element) as any View)
            }
        }
    }

    init(makeParts: @escaping @MainActor () -> [(Segment, any View)]) {
        self.makeParts = makeParts
    }

    /// Disfavored so that `ForEach($items)` over a Binding selects the id-keyed binding initializer.
    @_disfavoredOverload
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(items: data, idOf: { $0[keyPath: id] }, makeContent: content)
    }

    @MainActor public var body: Never { return fatalError("ForEach has no body") }

    var supportsRefreshSkip: Bool { true }

    @MainActor
    func parts() -> [(Segment, any View)] {
        makeParts()
    }
}

extension ForEach where ID == Data.Element.ID, Data.Element: Identifiable {
    @_disfavoredOverload
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

/// The observable value of one ForEach row, as last seen by the ForEach that owns the row. Row bodies read it instead of
/// the whole collection, so a change to one element wakes that row's nodes only.
@Observable
@MainActor
final class RowBox<Element, Index> {
    var value: Element
    /// Where the row sat in the collection at the last expansion; the row binding tries it first when it reads the live
    /// collection. Not observed: moving a row does not change what its views read.
    @ObservationIgnored var hint: Index
    init(_ value: Element, hint: Index) {
        self.value = value
        self.hint = hint
    }
}

/// The boxes of one ForEach, by row id. It lives as long as the ForEach value, so the rows of an owner that re-expands
/// the same ForEach (the data changed, nothing else) keep reading the same boxes.
@MainActor
final class RowStore<ID: Hashable, Element, Index> {
    var boxes: [ID: RowBox<Element, Index>] = [:]
}

/// Value equality for an element that may or may not be Equatable. An element that is not Equatable counts as changed.
@MainActor
func elementsEqual<T>(_ a: T, _ b: T) -> Bool {
    guard let equatable = a as? any Equatable else { return false }
    return equalErased(equatable, b)
}

@MainActor
private func equalErased<E: Equatable>(_ a: E, _ b: Any) -> Bool {
    guard let typed = b as? E else { return false }
    return typed == a
}

/// What a ForEach is being expanded under. `Graph.evaluate` sets it around `expand`; a ForEach over a binding reads its data
/// through `read` so the dependency belongs to that owner node and a change to the data re-expands the owner alone (and
/// only the rows whose element changed re-evaluate), instead of re-evaluating the body that built the ForEach.
@MainActor
enum ExpansionContext {
    static var owner: (graph: Graph, node: Node)?
    /// Ids of the rows this expansion saw new or with a changed element. The row views a ForEach builds can read the element
    /// directly (a bare `Text(row.wrappedValue.text)` has no body to track it), so the graph hands such a row its new view.
    static var changedRows: Set<AnyHashable> = []

    static func readData<T>(_ read: () -> T) -> T {
        guard let (graph, node) = owner else { return read() }
        return graph.trackData(of: node, read)
    }
}

/// Counts the observation tracking scopes of node evaluation that are open. A row binding read inside one registers on the
/// row's box; read anywhere else (an event handler, layout, resolution) it reads the live collection.
@MainActor
enum ObservationScope {
    static var depth = 0
    static var tracking: Bool { depth > 0 }
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
        let store = RowStore<ID, C.Element, C.Index>()
        self.init(makeParts: {
            let snapshot = ExpansionContext.readData { data.wrappedValue }
            var live = Set<ID>(minimumCapacity: snapshot.count)
            var parts: [(Segment, any View)] = []
            parts.reserveCapacity(snapshot.count)
            for position in snapshot.indices {
                let element = snapshot[position]
                let id = key(element)
                let box: RowBox<C.Element, C.Index>
                if let known = store.boxes[id] {
                    box = known
                    // A duplicate id reuses the first row's box (the graph keeps the first row of a duplicate id).
                    if live.insert(id).inserted {
                        known.hint = position
                        if !elementsEqual(known.value, element) {
                            known.value = element
                            ExpansionContext.changedRows.insert(AnyHashable(id))
                        }
                    }
                } else {
                    box = RowBox(element, hint: position)
                    store.boxes[id] = box
                    live.insert(id)
                    ExpansionContext.changedRows.insert(AnyHashable(id))
                }
                let fallback = element
                // The element is found by id, so a row handle never targets a stale index. The index it had at the last
                // expansion is tried first (one comparison); only a row that has moved since needs the scan, which then
                // remembers where it found the row.
                @MainActor func locate(_ current: C) -> C.Index? {
                    let hint = box.hint
                    if hint >= current.startIndex, hint < current.endIndex, key(current[hint]) == id { return hint }
                    guard let found = current.firstIndex(where: { key($0) == id }) else { return nil }
                    box.hint = found
                    return found
                }
                let row = Binding<C.Element>(
                    get: {
                        // Inside a node's observation scope the row reads its box (a dependency on this row alone);
                        // everywhere else the live collection, so an event handler never sees a stale value.
                        if ObservationScope.tracking { return box.value }
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
                parts.append((Segment.keyed(AnyHashable(id)), content(row) as any View))
            }
            if store.boxes.count != live.count { store.boxes = store.boxes.filter { live.contains($0.key) } }
            return parts
        })
    }
}

#if os(Windows)
// swift-corelibs Foundation on Windows lacks `remove(atOffsets:)` (Apple's Foundation has it since macOS 15, so macOS must not declare it twice).
extension RangeReplaceableCollection where Self: BidirectionalCollection {
    /// Removes the elements at `offsets`. Apple: https://developer.apple.com/documentation/swiftui/rangereplaceablecollection/remove(atoffsets:)
    public mutating func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.sorted(by: >) { remove(at: index(startIndex, offsetBy: offset)) }
    }
}
#endif

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

public enum Edge: Int8, CaseIterable, Sendable {
    case top = 0, leading, bottom, trailing

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

/// The vertical edges of a row (`listRowSeparator(_:edges:)`). Apple: https://developer.apple.com/documentation/swiftui/verticaledge
public enum VerticalEdge: Int8, CaseIterable, Sendable {
    case top, bottom

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1)
        public static let bottom = Set(rawValue: 2)
        public static let all: Set = [.top, .bottom]
    }
}


// MARK: - AnyView, View.id, ViewModifier

/// A type-erased view. It is transparent: the wrapped view's own node takes its place, one level down under an `.erased` segment, so a different wrapped type is a
/// different node (state is not carried across types, as in SwiftUI).
/// Apple: https://developer.apple.com/documentation/swiftui/anyview
public struct AnyView: View {
    nonisolated(unsafe) let wrapped: any View
    nonisolated public init<V: View>(_ view: V) { wrapped = view }
    nonisolated public init<V: View>(erasing view: V) { wrapped = view }
    @MainActor public var body: Never { return fatalError("AnyView has no body") }
}

extension AnyView: ViewContainer {
    var supportsRefreshSkip: Bool { false }
    @MainActor func parts() -> [(Segment, any View)] { [(.erased, wrapped)] }
}

/// `View.id(_:)`: the view's identity is the value, so a new value replaces the view (its `@State` restarts, its `onAppear` runs again).
struct IdentifiedView<Content: View>: View, ViewContainer {
    let content: Content
    let id: AnyHashable
    @MainActor public var body: Never { return fatalError("IdentifiedView has no body") }
    var supportsRefreshSkip: Bool { false }
    @MainActor func parts() -> [(Segment, any View)] { [(.identified(id), content)] }
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/id(_:)
    public func id<ID: Hashable>(_ id: ID) -> some View {
        IdentifiedView(content: self, id: AnyHashable(id))
    }
}

/// What `ViewModifier.body(content:)` receives: the modified view, transparent in the tree.
public struct _ViewModifier_Content<Modifier>: View, ViewContainer {
    let wrapped: any View
    @MainActor public var body: Never { return fatalError("ViewModifier content has no body") }
    var supportsRefreshSkip: Bool { false }
    @MainActor func parts() -> [(Segment, any View)] { [(.erased, wrapped)] }
}

/// Apple: https://developer.apple.com/documentation/swiftui/viewmodifier
@MainActor @preconcurrency
public protocol ViewModifier {
    associatedtype Body: View
    typealias Content = _ViewModifier_Content<Self>
    @ViewBuilder @MainActor func body(content: Content) -> Body
}

/// The view `.modifier(_:)` makes: its body is the modifier's body around the content. It is a user view, so the modifier's work (its own conditions, its
/// modifiers) is evaluated in the tree under this node.
struct ModifiedContentView<Modifier: ViewModifier, Base: View>: View {
    let modifier: Modifier
    let base: Base
    @MainActor var body: some View { modifier.body(content: _ViewModifier_Content(wrapped: base)) }
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/modifier(_:)
    public func modifier<M: ViewModifier>(_ modifier: M) -> some View {
        ModifiedContentView(modifier: modifier, base: self)
    }
}
