import Foundation
import Observation

// Issue #60 (SR1 backlog), first pass: NavigationStack, NavigationLink, NavigationPath, `navigationDestination(for:)`, NavigationSplitView, `navigationTitle`,
// `navigationSubtitle`, ToolbarItem, ToolbarItemGroup and `.toolbar`. All composed from existing views; no host painting is needed.
//
// HOW IT WORKS
// - A NavigationStack owns a `NavigationStackModel` (pushed screens) and passes it down in the environment. NavigationLink pushes onto it; `\.dismiss` and the bar's
//   back button pop it. The root and every pushed screen stay alive in a ZStack (so the root keeps its `@State`, as in SwiftUI); only the top one is visible and takes hits.
//   There is no push/pop animation and no swipe-back.
// - Value-based links (`NavigationLink(value:)`) look their screen up in the destinations registered by `.navigationDestination(for:)` (registered when the modifier's view
//   is evaluated; a registration anywhere under the stack, root or pushed screen, counts). A link with no matching destination pushes an empty screen.
// - `NavigationStack(path:)` with a `Binding<NavigationPath>` (or a binding to any `[Hashable]`) makes value pushes and pops write the binding, and a write to the binding
//   pushes or pops screens. Destination-based links in a path-bound stack are kept by the stack itself and are not part of the bound path (an adaptation: SwiftUI types them
//   into its internal path); they pop before bound values do.
// - `navigationTitle`, `navigationSubtitle` and `.toolbar` flow up as one preference (`NavigationBarInfoKey`) that the stack (or split view) turns into a BAR ROW above its
//   screens: a back button when something is pushed, `.navigation` / `.cancellationAction` items, the title (or the `.principal` item), then the other items on the trailing
//   side. A stack with nothing to show has no bar row. The preference value compares by placement and text (a view cannot be compared), so a toolbar item whose view changes
//   without changing its text (an icon swap) is not re-delivered until something else changes.
// - NavigationSplitView is a row of columns: the sidebar (215 pt), an optional content column (250 pt), then the detail (the rest). A NavigationLink inside a column
//   REPLACES the detail (value links need a `navigationDestination` too), as sidebar links do on macOS. `columnVisibility` hides the sidebar for `.detailOnly`.
//
// METRICS are guesses, not measured on macOS 27: bar row 52 pt tall with 12 pt side padding, 8 pt between items, title in `.headline`, subtitle in `.caption`;
// sidebar 215 pt, content column 250 pt, a hairline `Divider` between columns, the sidebar on a 8% grey ground (the host has no sidebar material).
// NavigationLink outside a List is a default Button (macOS draws it as a bordered button; the runtime's Button look is used). Not modelled: `navigationDestination(isPresented:)`,
// `navigationBarBackButtonHidden`, `.navigationSplitViewColumnWidth`, programmatic column collapse by user drag, toolbar customisation, `ToolbarItem(id:)`.

// MARK: - NavigationPath

/// A type-erased list of pushed values. Apple: https://developer.apple.com/documentation/swiftui/navigationpath
public struct NavigationPath: Equatable {
    var items: [AnyHashable]

    init(items: [AnyHashable]) { self.items = items }

    /// Apple: https://developer.apple.com/documentation/swiftui/navigationpath/init()
    public init() { items = [] }

    /// Apple: https://developer.apple.com/documentation/swiftui/navigationpath/init(_:)
    public init<S: Sequence>(_ elements: S) where S.Element: Hashable {
        items = elements.map { AnyHashable($0) }
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/navigationpath/count
    public var count: Int { items.count }
    /// Apple: https://developer.apple.com/documentation/swiftui/navigationpath/isempty
    public var isEmpty: Bool { items.isEmpty }

    /// Apple: https://developer.apple.com/documentation/swiftui/navigationpath/append(_:)
    public mutating func append<V: Hashable>(_ value: V) { items.append(AnyHashable(value)) }

    /// Apple: https://developer.apple.com/documentation/swiftui/navigationpath/removelast(_:)
    public mutating func removeLast(_ k: Int = 1) { items.removeLast(min(max(k, 0), items.count)) }
}

// MARK: - Toolbar content

/// Where a toolbar item goes. Only the macOS placements. Apple: https://developer.apple.com/documentation/swiftui/toolbaritemplacement
public struct ToolbarItemPlacement: Hashable, Sendable {
    let name: String
    private init(_ name: String) { self.name = name }

    public static let automatic = ToolbarItemPlacement("automatic")
    public static let principal = ToolbarItemPlacement("principal")
    public static let navigation = ToolbarItemPlacement("navigation")
    public static let primaryAction = ToolbarItemPlacement("primaryAction")
    public static let secondaryAction = ToolbarItemPlacement("secondaryAction")
    public static let status = ToolbarItemPlacement("status")
    public static let confirmationAction = ToolbarItemPlacement("confirmationAction")
    public static let cancellationAction = ToolbarItemPlacement("cancellationAction")
    public static let destructiveAction = ToolbarItemPlacement("destructiveAction")
}

/// Content of a toolbar. Only the runtime's own `ToolbarItem`, `ToolbarItemGroup` and builder results conform; a custom conformance (with a `body`) is not walked.
/// Apple: https://developer.apple.com/documentation/swiftui/toolbarcontent
public protocol ToolbarContent {}

/// One toolbar item as the bar shows it.
struct ToolbarEntry: Equatable {
    let placement: ToolbarItemPlacement
    let view: AnyView
    /// Text and type of the item: what comparison uses (views are not comparable).
    let signature: String

    static func == (lhs: ToolbarEntry, rhs: ToolbarEntry) -> Bool {
        lhs.placement == rhs.placement && lhs.signature == rhs.signature
    }

    @MainActor
    init<V: View>(placement: ToolbarItemPlacement, view: V) {
        self.placement = placement
        self.view = AnyView(view)
        signature = "\(type(of: view))|" + ViewWalk.plainText(view)
    }
}

@MainActor
protocol ToolbarEntrySource {
    func toolbarEntries() -> [ToolbarEntry]
}

@MainActor
func collectToolbarEntries(_ content: Any) -> [ToolbarEntry] {
    if let source = content as? any ToolbarEntrySource { return source.toolbarEntries() }
    let mirror = Mirror(reflecting: content)
    if mirror.displayStyle == .optional, let child = mirror.children.first { return collectToolbarEntries(child.value) }
    return []
}

/// Apple: https://developer.apple.com/documentation/swiftui/toolbaritem
@MainActor
public struct ToolbarItem<ID, Content: View>: ToolbarContent, ToolbarEntrySource {
    let placement: ToolbarItemPlacement
    let content: Content

    func toolbarEntries() -> [ToolbarEntry] { [ToolbarEntry(placement: placement, view: content)] }
}

extension ToolbarItem where ID == Void {
    /// Apple: https://developer.apple.com/documentation/swiftui/toolbaritem/init(placement:content:)
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }
}

/// Several views in one placement, shown side by side. Apple: https://developer.apple.com/documentation/swiftui/toolbaritemgroup
@MainActor
public struct ToolbarItemGroup<Content: View>: ToolbarContent, ToolbarEntrySource {
    let placement: ToolbarItemPlacement
    let content: Content

    /// Apple: https://developer.apple.com/documentation/swiftui/toolbaritemgroup/init(placement:content:)
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    func toolbarEntries() -> [ToolbarEntry] { [ToolbarEntry(placement: placement, view: HStack(spacing: 8) { content })] }
}

/// What `ToolbarContentBuilder` makes of several items (and of a conditional).
@MainActor
public struct _ToolbarTuple: ToolbarContent, ToolbarEntrySource {
    let items: [Any]
    init(items: [Any]) { self.items = items }

    func toolbarEntries() -> [ToolbarEntry] { items.flatMap { collectToolbarEntries($0) } }
}

extension Optional: ToolbarContent where Wrapped: ToolbarContent {}

/// Apple: https://developer.apple.com/documentation/swiftui/toolbarcontentbuilder
@MainActor @preconcurrency
@resultBuilder
public struct ToolbarContentBuilder {
    public static func buildBlock() -> _ToolbarTuple { _ToolbarTuple(items: []) }
    public static func buildBlock<C: ToolbarContent>(_ content: C) -> C { content }
    public static func buildBlock<each C: ToolbarContent>(_ content: repeat each C) -> _ToolbarTuple {
        var items: [Any] = []
        for item in repeat each content { items.append(item) }
        return _ToolbarTuple(items: items)
    }
    public static func buildIf<C: ToolbarContent>(_ content: C?) -> C? { content }
    public static func buildEither(first content: some ToolbarContent) -> _ToolbarTuple { _ToolbarTuple(items: [content]) }
    public static func buildEither(second content: some ToolbarContent) -> _ToolbarTuple { _ToolbarTuple(items: [content]) }
}

// MARK: - The bar preference

/// Title, subtitle and toolbar items that the views of a screen contribute upward.
struct NavigationBarInfo: Equatable {
    var title: String? = nil
    var subtitle: String? = nil
    var items: [ToolbarEntry] = []

    var isEmpty: Bool { title == nil && subtitle == nil && items.isEmpty }
}

enum NavigationBarInfoKey: PreferenceKey {
    static var defaultValue: NavigationBarInfo { NavigationBarInfo() }

    /// The later title or subtitle wins; items accumulate in tree order.
    static func reduce(value: inout NavigationBarInfo, nextValue: () -> NavigationBarInfo) {
        let next = nextValue()
        if let title = next.title { value.title = title }
        if let subtitle = next.subtitle { value.subtitle = subtitle }
        value.items += next.items
    }
}

extension View {
    /// The title the enclosing NavigationStack or NavigationSplitView shows in its bar row.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/navigationtitle(_:)
    public func navigationTitle(_ title: String) -> some View {
        Modified(content: self, spec: .preference(PreferenceContribution(NavigationBarInfo(title: title), for: NavigationBarInfoKey.self)))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:)
    public func navigationSubtitle(_ subtitle: String) -> some View {
        Modified(content: self, spec: .preference(PreferenceContribution(NavigationBarInfo(subtitle: subtitle), for: NavigationBarInfoKey.self)))
    }

    /// Adds toolbar items to the enclosing NavigationStack's or NavigationSplitView's bar row (placement decides the side; see the file header).
    /// Apple: https://developer.apple.com/documentation/swiftui/view/toolbar(content:)
    public func toolbar<Content: ToolbarContent>(@ToolbarContentBuilder content: () -> Content) -> some View {
        let info = NavigationBarInfo(items: collectToolbarEntries(content()))
        return Modified(content: self, spec: .preference(PreferenceContribution(info, for: NavigationBarInfoKey.self)))
    }

    /// Plain views as toolbar items, in the automatic placement. Apple: https://developer.apple.com/documentation/swiftui/view/toolbar(content:)
    public func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let info = NavigationBarInfo(items: [ToolbarEntry(placement: .automatic, view: content())])
        return Modified(content: self, spec: .preference(PreferenceContribution(info, for: NavigationBarInfoKey.self)))
    }
}

// MARK: - The bar row

enum NavigationBarMetrics {
    /// Guess: a unified macOS toolbar is about 52 pt tall.
    static let height: CGFloat = 52
    static let sidePadding: CGFloat = 12
    static let itemSpacing: CGFloat = 8
}

struct NavigationBarRow: View {
    let info: NavigationBarInfo
    let canGoBack: Bool
    let goBack: () -> Void

    @MainActor var body: some View {
        let numbered = Array(info.items.enumerated())
        let leading = numbered.filter { $0.element.placement == .navigation || $0.element.placement == .cancellationAction }
        let principal = numbered.filter { $0.element.placement == .principal }
        let trailing = numbered.filter {
            $0.element.placement != .navigation && $0.element.placement != .cancellationAction && $0.element.placement != .principal
        }
        HStack(spacing: NavigationBarMetrics.itemSpacing) {
            if canGoBack {
                Button(action: goBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
            }
            ForEach(leading, id: \.offset) { pair in pair.element.view }
            if principal.isEmpty {
                if let title = info.title {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(.headline)
                        if let subtitle = info.subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(Color.secondary)
                        }
                    }
                }
            } else {
                ForEach(principal, id: \.offset) { pair in pair.element.view }
            }
            Spacer()
            ForEach(trailing, id: \.offset) { pair in pair.element.view }
        }
        .padding(.horizontal, NavigationBarMetrics.sidePadding)
        .frame(height: NavigationBarMetrics.height)
    }
}

/// A bar row above `content`, fed by the bar preference of `content`. The row is absent while there is nothing to show. The preference stops here (an enclosing
/// stack or split view does not show a nested stack's bar twice).
struct NavigationBarHost<Content: View>: View {
    let content: Content
    let canGoBack: Bool
    let goBack: () -> Void
    @State private var info = NavigationBarInfo()

    @MainActor var body: some View {
        let state = _info
        VStack(spacing: 0) {
            if canGoBack || !info.isEmpty {
                NavigationBarRow(info: info, canGoBack: canGoBack, goBack: goBack)
                Divider()
            }
            content
                .onPreferenceChange(NavigationBarInfoKey.self) { state.wrappedValue = $0 }
                .transformPreference(NavigationBarInfoKey.self) { $0 = NavigationBarInfo() }
        }
    }
}

// MARK: - Stack model

/// What a link or the bar reaches through the environment.
@Observable
@MainActor
final class NavigationStackModel {
    struct Pushed {
        enum Kind {
            case view(AnyView)
            case value(AnyHashable)
        }
        let id: Int
        let kind: Kind
    }

    /// Screens pushed by destination links (and by value links when no path is bound). Observed: the stack re-evaluates when it changes.
    var local: [Pushed] = []
    @ObservationIgnored var nextID = 0
    @ObservationIgnored var destinations: [ObjectIdentifier: (Any) -> AnyView?] = [:]
    @ObservationIgnored var path: NavigationPathAccess?
    /// A NavigationSplitView's model: a link replaces the detail instead of stacking.
    @ObservationIgnored var replacesTop = false

    /// Bound path values first, then local pushes: the screens in order, root excluded.
    func entries() -> [NavigationStackEntry] {
        var out: [NavigationStackEntry] = []
        if let path {
            for (index, value) in path.read().enumerated() {
                out.append(NavigationStackEntry(id: AnyHashable(PathEntryID(index: index, value: value)), kind: .value(value)))
            }
        }
        for pushed in local {
            out.append(NavigationStackEntry(id: AnyHashable(pushed.id), kind: pushed.kind))
        }
        return out
    }

    private func append(_ kind: Pushed.Kind) {
        if replacesTop { local.removeAll() }
        nextID += 1
        local.append(Pushed(id: nextID, kind: kind))
    }

    func push(view: AnyView) { append(.view(view)) }

    func push(value: AnyHashable) {
        if let path, !replacesTop {
            path.write(path.read() + [value])
        } else {
            append(.value(value))
        }
    }

    /// Removes the top screen: a local push first, else the last bound path value.
    func pop() {
        if !local.isEmpty {
            local.removeLast()
        } else if let path {
            var values = path.read()
            guard !values.isEmpty else { return }
            values.removeLast()
            path.write(values)
        }
    }

    func register<D: Hashable>(_ type: D.Type, _ make: @escaping (D) -> AnyView) {
        destinations[ObjectIdentifier(type)] = { any in (any as? D).map(make) }
    }

    func resolve(_ value: AnyHashable) -> AnyView? {
        destinations[ObjectIdentifier(Swift.type(of: value.base))]?(value.base)
    }
}

struct PathEntryID: Hashable {
    let index: Int
    let value: AnyHashable
}

/// Reads and writes the bound path as type-erased values.
struct NavigationPathAccess {
    let read: @MainActor () -> [AnyHashable]
    let write: @MainActor ([AnyHashable]) -> Void
}

struct NavigationStackEntry {
    let id: AnyHashable
    let kind: NavigationStackModel.Pushed.Kind
}

private enum NavigationStackModelKey: EnvironmentKey {
    static var defaultValue: NavigationStackModel? { nil }
}

extension EnvironmentValues {
    var navigationStackModel: NavigationStackModel? {
        get { self[NavigationStackModelKey.self] }
        set { self[NavigationStackModelKey.self] = newValue }
    }
}

// MARK: - Screens

/// A value-based screen: the destination registered for the value's type.
struct NavigationValueScreen: View {
    let value: AnyHashable
    let model: NavigationStackModel

    @MainActor var body: some View {
        if let screen = model.resolve(value) {
            screen
        } else {
            EmptyView()
        }
    }
}

/// One pushed screen: visible and hit-testable only while it is the top one, and its bar contributions count only then.
struct NavigationPushedScreen: View {
    let entry: NavigationStackEntry
    let isTop: Bool
    let model: NavigationStackModel

    @ViewBuilder
    @MainActor private var screen: some View {
        switch entry.kind {
        case .view(let view):
            view
        case .value(let value):
            NavigationValueScreen(value: value, model: model)
        }
    }

    @MainActor var body: some View {
        let top = isTop
        screen
            .transformPreference(NavigationBarInfoKey.self) { if !top { $0 = NavigationBarInfo() } }
            .opacity(top ? 1 : 0)
            .allowsHitTesting(top)
            .environment(\.dismiss, DismissAction(perform: { [model] in model.pop() }))
    }
}

/// The root and the pushed screens, stacked.
struct NavigationScreens<Root: View>: View {
    let root: Root
    let entries: [NavigationStackEntry]
    let model: NavigationStackModel

    @MainActor var body: some View {
        let covered = !entries.isEmpty
        let topID = entries.last?.id
        ZStack {
            root
                .transformPreference(NavigationBarInfoKey.self) { if covered { $0 = NavigationBarInfo() } }
                .opacity(covered ? 0 : 1)
                .allowsHitTesting(!covered)
            ForEach(entries, id: \.id) { entry in
                NavigationPushedScreen(entry: entry, isTop: entry.id == topID, model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - NavigationStack

/// A stack of screens: the root, and whatever `NavigationLink`s pushed. Apple: https://developer.apple.com/documentation/swiftui/navigationstack
public struct NavigationStack<Data, Root: View>: View {
    let root: Root
    let pathAccess: NavigationPathAccess?
    @State private var model = NavigationStackModel()

    init(root: Root, pathAccess: NavigationPathAccess?) {
        self.root = root
        self.pathAccess = pathAccess
    }

    @MainActor private func prepared() -> NavigationStackModel {
        let current = model
        current.path = pathAccess
        return current
    }

    @MainActor public var body: some View {
        let current = prepared()
        let entries = current.entries()
        NavigationBarHost(
            content: NavigationScreens(root: root, entries: entries, model: current),
            canGoBack: !entries.isEmpty,
            goBack: { current.pop() }
        )
        .environment(\.navigationStackModel, current)
    }
}

extension NavigationStack where Data == NavigationPath {
    /// Apple: https://developer.apple.com/documentation/swiftui/navigationstack/init(root:)
    public init(@ViewBuilder root: () -> Root) {
        self.init(root: root(), pathAccess: nil)
    }

    /// Value pushes and pops write `path`; a write to `path` pushes or pops screens. Apple: https://developer.apple.com/documentation/swiftui/navigationstack/init(path:root:)
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) {
        self.init(root: root(), pathAccess: NavigationPathAccess(
            read: { path.wrappedValue.items },
            write: { path.wrappedValue = NavigationPath(items: $0) }
        ))
    }
}

extension NavigationStack {
    /// A path of one value type. Apple: https://developer.apple.com/documentation/swiftui/navigationstack/init(path:root:)
    public init(path: Binding<Data>, @ViewBuilder root: () -> Root)
    where Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection, Data.Element: Hashable {
        self.init(root: root(), pathAccess: NavigationPathAccess(
            read: { path.wrappedValue.map { AnyHashable($0) } },
            write: { values in path.wrappedValue = Data(values.compactMap { $0.base as? Data.Element }) }
        ))
    }
}

// MARK: - NavigationLink

/// A button that pushes a screen onto the enclosing NavigationStack (or replaces the detail of a NavigationSplitView). Outside both it does nothing.
/// Apple: https://developer.apple.com/documentation/swiftui/navigationlink
public struct NavigationLink<Label: View, Destination: View>: View {
    enum Target {
        case destination(AnyView)
        case value(AnyHashable?)
    }

    let label: Label
    let target: Target
    @Environment(\.navigationStackModel) private var stack

    init(label: Label, target: Target) {
        self.label = label
        self.target = target
    }

    @MainActor private func follow() {
        guard let stack else { return }
        switch target {
        case .destination(let view): stack.push(view: view)
        case .value(let value): if let value { stack.push(value: value) }
        }
    }

    @MainActor public var body: some View {
        Button(action: { follow() }) { label }
    }
}

extension NavigationLink {
    /// Apple: https://developer.apple.com/documentation/swiftui/navigationlink/init(destination:label:)
    public init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.init(label: label(), target: .destination(AnyView(destination)))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/navigationlink/init(destination:label:)
    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.init(label: label(), target: .destination(AnyView(destination())))
    }
}

extension NavigationLink where Label == Text {
    /// Apple: https://developer.apple.com/documentation/swiftui/navigationlink/init(_:destination:)
    public init(_ title: String, destination: Destination) {
        self.init(label: Text(title), target: .destination(AnyView(destination)))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/navigationlink/init(_:destination:)
    public init(_ title: String, @ViewBuilder destination: () -> Destination) {
        self.init(label: Text(title), target: .destination(AnyView(destination())))
    }
}

extension NavigationLink where Destination == Never {
    /// A link that pushes `value`; the screen comes from a `navigationDestination(for:)`. A nil value does nothing.
    /// Apple: https://developer.apple.com/documentation/swiftui/navigationlink/init(value:label:)
    public init<P: Hashable>(value: P?, @ViewBuilder label: () -> Label) {
        self.init(label: label(), target: .value(value.map { AnyHashable($0) }))
    }
}

extension NavigationLink where Label == Text, Destination == Never {
    /// Apple: https://developer.apple.com/documentation/swiftui/navigationlink/init(_:value:)
    public init<P: Hashable>(_ title: String, value: P?) {
        self.init(label: Text(title), target: .value(value.map { AnyHashable($0) }))
    }
}

/// Registers the screen a pushed value of one type shows.
struct NavigationDestinationHost<Base: View, D: Hashable, Screen: View>: View {
    let base: Base
    let destination: (D) -> Screen
    @Environment(\.navigationStackModel) private var stack

    @MainActor var body: some View {
        let _ = stack?.register(D.self) { AnyView(destination($0)) }
        base
    }
}

extension View {
    /// The screen a `NavigationLink(value:)` (or a bound path value) of type `D` pushes.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:)
    public func navigationDestination<D: Hashable, C: View>(for data: D.Type, @ViewBuilder destination: @escaping (D) -> C) -> some View {
        NavigationDestinationHost(base: self, destination: destination)
    }
}

// MARK: - NavigationSplitView

/// Which columns of a split view show. Apple: https://developer.apple.com/documentation/swiftui/navigationsplitviewvisibility
public enum NavigationSplitViewVisibility: Hashable, Sendable {
    case automatic
    case all
    case doubleColumn
    case detailOnly
}

enum NavigationSplitMetrics {
    static let sidebarWidth: CGFloat = 215
    static let contentWidth: CGFloat = 250
}

struct NavigationSplitColumns<Sidebar: View, Content: View, Detail: View>: View {
    let sidebar: Sidebar
    let content: Content
    let detail: Detail
    let hasContent: Bool
    let visibility: NavigationSplitViewVisibility
    let model: NavigationStackModel

    @MainActor var body: some View {
        let showDetailOnly = visibility == .detailOnly
        let showSidebar = !showDetailOnly && (!hasContent || visibility == .all || visibility == .automatic)
        let showContent = hasContent && !showDetailOnly
        let replaced = model.entries().last
        HStack(spacing: 0) {
            if showSidebar {
                sidebar
                    .frame(width: NavigationSplitMetrics.sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.08))
                Divider()
            }
            if showContent {
                content
                    .frame(width: NavigationSplitMetrics.contentWidth)
                    .frame(maxHeight: .infinity)
                Divider()
            }
            ZStack {
                detail
                    .transformPreference(NavigationBarInfoKey.self) { if replaced != nil { $0 = NavigationBarInfo() } }
                    .opacity(replaced == nil ? 1 : 0)
                    .allowsHitTesting(replaced == nil)
                if let replaced {
                    NavigationPushedScreen(entry: replaced, isTop: true, model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Two or three columns side by side. Apple: https://developer.apple.com/documentation/swiftui/navigationsplitview
public struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View {
    let sidebar: Sidebar
    let content: Content
    let detail: Detail
    let hasContent: Bool
    let visibility: Binding<NavigationSplitViewVisibility>?
    @State private var model = NavigationStackModel()

    init(sidebar: Sidebar, content: Content, detail: Detail, hasContent: Bool, visibility: Binding<NavigationSplitViewVisibility>?) {
        self.sidebar = sidebar
        self.content = content
        self.detail = detail
        self.hasContent = hasContent
        self.visibility = visibility
    }

    @MainActor private func prepared() -> NavigationStackModel {
        let current = model
        current.replacesTop = true
        return current
    }

    @MainActor public var body: some View {
        let current = prepared()
        NavigationBarHost(
            content: NavigationSplitColumns(
                sidebar: sidebar, content: content, detail: detail, hasContent: hasContent,
                visibility: visibility?.wrappedValue ?? .automatic, model: current
            ),
            canGoBack: false,
            goBack: {}
        )
        .environment(\.navigationStackModel, current)
    }
}

extension NavigationSplitView where Content == EmptyView {
    /// Apple: https://developer.apple.com/documentation/swiftui/navigationsplitview/init(sidebar:detail:)
    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
        self.init(sidebar: sidebar(), content: EmptyView(), detail: detail(), hasContent: false, visibility: nil)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/navigationsplitview/init(columnvisibility:sidebar:detail:)
    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.init(sidebar: sidebar(), content: EmptyView(), detail: detail(), hasContent: false, visibility: columnVisibility)
    }
}

extension NavigationSplitView {
    /// Apple: https://developer.apple.com/documentation/swiftui/navigationsplitview/init(sidebar:content:detail:)
    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.init(sidebar: sidebar(), content: content(), detail: detail(), hasContent: true, visibility: nil)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/navigationsplitview/init(columnvisibility:sidebar:content:detail:)
    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.init(sidebar: sidebar(), content: content(), detail: detail(), hasContent: true, visibility: columnVisibility)
    }
}
