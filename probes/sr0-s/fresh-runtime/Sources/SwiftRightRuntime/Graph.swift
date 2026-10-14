import Foundation
import Observation

// MARK: - Identity

/// The name of a leaf view type, built once per metatype (reflecting a type name allocates and demangles). Segments compare
/// and hash it by identity, so node identity never walks the characters of a type name.
final class TypeName: @unchecked Sendable {
    let full: String
    let short: String
    let key: Int

    init(_ type: Any.Type) {
        full = String(reflecting: type)
        short = shortName(full)
        key = Int(bitPattern: ObjectIdentifier(type))
    }

    /// A name that stands for no real view type (the graph root).
    init(_ type: Any.Type, display: String) {
        full = display
        short = display
        key = Int(bitPattern: ObjectIdentifier(type))
    }
}

/// One step of a structural path. Positional segments come from the builder (tuple index,
/// Either branch, Optional presence); keyed segments come from explicit ForEach ids.
enum Segment: Hashable, CustomStringConvertible {
    case type(TypeName)      // leaf view type (identity); displayed short
    case index(Int)          // position inside a builder tuple
    case branch(Int)         // ConditionalContent arm
    case optional            // Optional<View> presence
    case keyed(AnyHashable)  // ForEach explicit id

    var description: String {
        switch self {
        case .type(let name): return name.short
        case .index(let i): return "#\(i)"
        case .branch(let i): return "branch\(i)"
        case .optional: return "opt"
        case .keyed(let value): return "[\(value)]"
        }
    }

    static func == (lhs: Segment, rhs: Segment) -> Bool {
        switch (lhs, rhs) {
        case (.type(let a), .type(let b)): return a === b
        case (.index(let a), .index(let b)): return a == b
        case (.branch(let a), .branch(let b)): return a == b
        case (.optional, .optional): return true
        case (.keyed(let a), .keyed(let b)): return a == b
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(mixKey) }

    /// A cheap integer standing for this segment in the path hash.
    var mixKey: Int {
        switch self {
        case .type(let name): return name.key
        case .index(let i): return i &+ 0x1_0000_0001
        case .branch(let i): return i &+ 0x2_0000_0003
        case .optional: return 0x3_0000_0007
        case .keyed(let value): return value.hashValue
        }
    }
}

func shortName(_ fullName: String) -> String {
    let head = fullName.prefix { $0 != "<" }
    return String(head.split(separator: ".").last ?? Substring(head))
}

public struct NodeID: Hashable, CustomStringConvertible {
    let segments: [Segment]
    /// Order-sensitive digest of `segments`, computed incrementally when a child id is built from its parent's.
    let key: Int

    init(segments: [Segment]) {
        self.segments = segments
        key = segments.reduce(NodeID.seed) { NodeID.mix($0, $1.mixKey) }
    }

    init(parent: NodeID, relative: [Segment]) {
        segments = parent.segments + relative
        key = relative.reduce(parent.key) { NodeID.mix($0, $1.mixKey) }
    }

    private static let seed = 0x1000_0000_01B3
    @inline(__always)
    private static func mix(_ hash: Int, _ part: Int) -> Int { (hash ^ part) &* 0x1000_0000_01B3 }

    public static func == (lhs: NodeID, rhs: NodeID) -> Bool { lhs.key == rhs.key && lhs.segments == rhs.segments }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }
    public var description: String { segments.map(\.description).joined(separator: "/") }
}

/// Type facts that never change for a view type, looked up once per metatype instead of by reflection on every evaluation.
@MainActor
enum ViewTypes {
    enum Shape {
        case empty
        case container
        case optional
        case leaf
    }

    struct Info {
        let name: TypeName
        let shape: Shape
        /// True when a stored property is `@State`, `@FocusState` or `@Environment` (a dynamic property).
        let hasDynamicProperties: Bool
        /// Reads a primitive view's kind and content. Nil for a user view. Built once per type, so reading a view of that type
        /// needs a cast to the concrete type only, not a conformance lookup.
        let readPrimitive: (@MainActor (any View) -> (kind: NodeKind, content: (any View)?))?
    }

    private static var cache: [ObjectIdentifier: Info] = [:]
    static var cacheCount: Int { cache.count }

    static func info(for view: any View) -> Info {
        let type = type(of: view)
        let key = ObjectIdentifier(type)
        if let found = cache[key] { return found }
        let shape: Shape
        if view is EmptyView { shape = .empty }
        else if view is any ViewContainer { shape = .container }
        else if view is any OptionalViewBox { shape = .optional }
        else { shape = .leaf }
        var dynamic = false
        var reader: (@MainActor (any View) -> (kind: NodeKind, content: (any View)?))?
        if shape == .leaf {
            dynamic = Mirror(reflecting: view).children.contains { $0.value is DynamicPropertyStorage }
            if let primitive = view as? any (PrimitiveView & View) { reader = makeReader(primitive) }
        }
        let info = Info(name: TypeName(type), shape: shape, hasDynamicProperties: dynamic, readPrimitive: reader)
        cache[key] = info
        return info
    }

    private static func makeReader<P: PrimitiveView & View>(_ sample: P) -> @MainActor (any View) -> (kind: NodeKind, content: (any View)?) {
        { view in
            let primitive = view as! P
            return (primitive.nodeKind, primitive.nodeContent)
        }
    }
}

/// `Optional<Wrapped>` where the wrapped value is a view: the child to expand, nil when absent.
@MainActor
protocol OptionalViewBox {
    var wrappedView: (any View)? { get }
}

extension Optional: @MainActor OptionalViewBox where Wrapped: View {
    var wrappedView: (any View)? {
        switch self {
        case .some(let view): return view
        case .none: return nil
        }
    }
}

// MARK: - Node

/// Type-erased focus binding of one `.focused(_:equals:)` modifier.
@MainActor
struct FocusLink {
    /// Identity of the observable box this link reads. Two links with the same identity depend on the same observable.
    let storage: ObjectIdentifier
    /// True when the bound focus names this modifier's value.
    let isFocused: () -> Bool
    /// Makes this modifier's value the focus.
    let focus: () -> Void
    /// Clears the focus only while it still names this modifier's value.
    let release: () -> Void
}

enum ModifierSpec {
    case padding(EdgeInsets)
    case frame(FrameSpec)
    case flexibleFrame(FlexibleFrameSpec)
    case appear(() -> Void)
    case disappear(() -> Void)
    /// `id` is nil for `task(name:...)`; a non-nil id restarts the task when it changes.
    case task(TaskPriority, AnyEquatable?, @isolated(any) () async -> Void)
    case focus(FocusLink)
    case animation(AnyEquatable, Animation?)
    /// `.onChange(of:initial:_:)`: the observed value, whether the first evaluation also runs the action, and the
    /// type-erased action `(old, new)`. The previous value (the baseline) is kept in `Node.storage`, not on the
    /// node, so a List that restores a reinserted row's `@State` restores the baseline with it.
    case onChange(AnyEquatable, Bool, (Any, Any) -> Void)
    case environment((inout EnvironmentValues) -> Void)
    case preference(PreferenceContribution)
    case onPreferenceChange(PreferenceObserver)
    case opacity(Double)
    /// SR1 round 3: `.transition(_:)`, read from the inserted subtree's top by the insertion animation.
    case transition(AnyTransition)
    /// SR1: `.tag(_:)` value of a List row.
    case tag(AnyHashable)
    /// SR1: the `onDelete` hook of a List row.
    case deletion(DeletionHook)
    /// SR1 block 16: the `onMove` hook of a List row.
    case movement(MoveHook)
    /// SR1: a context menu's content, evaluated into `Node.menuEntries`.
    case contextMenu(any View)
    /// SR1: an alert or confirmation dialog, presented while its binding is true.
    case presentation(PresentationPayload)
    case keyboardShortcut(KeyEquivalent, EventModifiers)
    case accessibilityLabel(String)

    /// "modifier." plus `name`, as resolved records show it (static strings, no allocation per commit).
    var kindName: String {
        switch self {
        case .padding: return "modifier.padding"
        case .frame: return "modifier.frame"
        case .flexibleFrame: return "modifier.frame"
        case .appear: return "modifier.onAppear"
        case .disappear: return "modifier.onDisappear"
        case .task: return "modifier.task"
        case .focus: return "modifier.focused"
        case .animation: return "modifier.animation"
        case .onChange: return "modifier.onChange"
        case .environment: return "modifier.environment"
        case .preference: return "modifier.preference"
        case .onPreferenceChange: return "modifier.onPreferenceChange"
        case .opacity: return "modifier.opacity"
        case .transition: return "modifier.transition"
        case .tag: return "modifier.tag"
        case .deletion: return "modifier.onDelete"
        case .movement: return "modifier.onMove"
        case .contextMenu: return "modifier.contextMenu"
        case .presentation(let payload):
            return payload.kind == .alert ? "modifier.alert" : "modifier.confirmationDialog"
        case .keyboardShortcut: return "modifier.keyboardShortcut"
        case .accessibilityLabel: return "modifier.accessibilityLabel"
        }
    }

    var name: String {
        switch self {
        case .padding: return "padding"
        case .frame: return "frame"
        case .flexibleFrame: return "frame"
        case .appear: return "onAppear"
        case .disappear: return "onDisappear"
        case .task: return "task"
        case .focus: return "focused"
        case .animation: return "animation"
        case .onChange: return "onChange"
        case .environment: return "environment"
        case .preference: return "preference"
        case .onPreferenceChange: return "onPreferenceChange"
        case .opacity: return "opacity"
        case .transition: return "transition"
        case .tag: return "tag"
        case .deletion: return "onDelete"
        case .movement: return "onMove"
        case .contextMenu: return "contextMenu"
        case .presentation(let payload):
            return payload.kind == .alert ? "alert" : "confirmationDialog"
        case .keyboardShortcut: return "keyboardShortcut"
        case .accessibilityLabel: return "accessibilityLabel"
        }
    }
}

enum NodeKind {
    case user
    case text(String)
    case spacer(CGFloat)
    case button(() -> Void)
    case textField(Binding<String>)
    case stack(StackSpec)
    case layout(LayoutSpec)
    /// Vertical scroll container. Its scroll offset lives on the node.
    case scroll
    /// Axis-configured scroll container. Kept separate so legacy layout remains unchanged.
    case scrollView(ScrollViewConfiguration)
    case modifier(ModifierSpec)
    /// SR1 controls. Toggle keeps its label as the child; the others are leaves or model-only.
    case toggle(Binding<Bool>)
    case image(ImageSpec)
    case color(ResolvedColor)
    case textEditor(Binding<String>)
    case divider
    case shape(ResolvedShape)
    /// Menu label is the child; its items are a model (`Node.menuEntries`).
    case menu

    /// True for the modifier that edits the environment its content sees.
    var changesEnvironment: Bool {
        if case .modifier(.environment) = self { return true }
        return false
    }

    /// Wrappers whose geometry is their single child's geometry (user bodies, buttons, and
    /// modifiers other than padding).
    var passesThrough: Bool {
        switch self {
        case .user, .button: return true
        case .modifier(.padding): return false
        case .modifier(.frame): return true
        case .modifier: return true
        default: return false
        }
    }
}

struct ScrollViewConfiguration: Equatable {
    var axes: Axis.Set
    var showsIndicators: Bool
}

struct AnyEquatable {
    let value: Any
    private let equals: (Any) -> Bool
    init<V: Equatable>(_ value: V) {
        self.value = value
        equals = { ($0 as? V) == value }
    }
    func matches(_ other: Any) -> Bool { equals(other) }
}

/// Key of an `.onChange` node's baseline in `Node.storage`. `@State` keys are property names, so this cannot collide.
let onChangeKey = "<onChange>"

/// The last value an `.onChange(of:)` node saw. A class so that it is a legal `Node.storage` value and travels with
/// retained List row state.
final class OnChangeBaseline {
    var value: AnyEquatable
    init(_ value: AnyEquatable) { self.value = value }
}

/// Per-List cache of `@State` storage and focus for keyed rows removed from that List (SR0-O F3
/// oracle: macOS 27 `List` preserves row state across remove → reinsert of the same id, and restores
/// focus to the reinserted row; VStack and LazyVStack reset both). Removal always clears focus and
/// runs onDisappear and task cancel; reinsertion always runs onAppear and restarts tasks.
///
/// Lifetime (PROVISIONAL, pending more oracle traces): the cache lives as long as the List node.
/// It is bounded to `limit` retired rows; the oldest-retired row is evicted first. A reinsert
/// consumes its entries. Entries for a row are replaced when that row is retired again.
struct RowStateCache {
    /// Provisional bound. Not yet checked against a long-gap or many-row oracle trace.
    static let limit = 64

    private var storage: [NodeID: [String: AnyObject]] = [:]
    /// Retired nodes that held focus when they were removed.
    private var focused: Set<NodeID> = []
    /// Retained node ids grouped by the top-level row (the List child) they came from.
    private var groups: [NodeID: [NodeID]] = [:]
    /// Top-level rows in retirement order, oldest first.
    private var order: [NodeID] = []

    /// Starts a fresh retention group for one retired top-level row, replacing any earlier one.
    mutating func beginRetiring(_ top: NodeID) {
        for id in groups.removeValue(forKey: top) ?? [] { forget(id) }
        order.removeAll { $0 == top }
        order.append(top)
        groups[top] = []
    }

    mutating func retain(_ id: NodeID, top: NodeID, state: [String: AnyObject], wasFocused: Bool) {
        if state.isEmpty && !wasFocused { return }
        storage[id] = state.isEmpty ? nil : state
        if wasFocused { focused.insert(id) }
        groups[top, default: []].append(id)
    }

    mutating func take(_ id: NodeID) -> [String: AnyObject]? {
        storage.removeValue(forKey: id)
    }

    mutating func takeFocus(_ id: NodeID) -> Bool {
        focused.remove(id) != nil
    }

    /// Entries held (diagnostics).
    var entryCount: Int { storage.count + focused.count + groups.count + order.count }

    mutating func trim() {
        while order.count > RowStateCache.limit {
            let evicted = order.removeFirst()
            for id in groups.removeValue(forKey: evicted) ?? [] { forget(id) }
        }
    }

    private mutating func forget(_ id: NodeID) {
        storage[id] = nil
        focused.remove(id)
    }
}

/// Observation registrations last until one of their properties changes. A node that is evaluated again without a change would
/// stack a new registration on top of the live one, and the stack grows with every evaluation (a registration on a property that
/// never changes is never released). Each tracked node therefore reads one of these inside its tracking scope: bumping it before
/// the node is tracked again fires, and so cancels, the previous registration.
@Observable
@MainActor
final class Tether {
    var version = 0
}

/// Weak link from owner tokens and observation callbacks to a node. Holding a handle never keeps
/// a node alive, which is what lets a torn-down tree be released.
@MainActor
final class NodeHandle {
    weak var node: Node?
}

@MainActor
final class Node {
    let id: NodeID
    /// The segments after the parent's path: the node's key among its siblings.
    let relative: [Segment]
    let handle: NodeHandle
    weak var parent: Node?
    private(set) var view: any View
    private(set) var info: ViewTypes.Info

    /// Replaces the node's view (and its type facts) with a new evaluation's.
    func setView(_ newView: any View, info newInfo: ViewTypes.Info) {
        view = newView
        info = newInfo
        kindResolved = false
        viewReplaced = true
    }
    var inherited = EnvironmentValues()
    var inheritedEnabled = true
    var inheritedStyle = ResolvedStyle(font: nil, foreground: nil)
    var environment = EnvironmentValues()
    var children: [NodeID] = []
    /// The live child nodes, parallel to `children`.
    var childNodes: [Node] = []
    private var kindResolved = false
    private var kindCache: NodeKind = .user
    private var contentCache: (any View)?
    private var idStringCache: String?
    /// The id as a string, built once.
    var idString: String {
        if let idStringCache { return idStringCache }
        let built = id.description
        idStringCache = built
        return built
    }
    /// Measured sizes of this subtree by proposal. Cleared when this node or a descendant is evaluated.
    var sizeCache: [ProposedViewSize: LayoutSize] = [:]
    /// Target frame and opacity as of the last change detection (the "before" side of the next commit's diff).
    var snapFrame: LayoutRect = .zero
    var snapOpacity: Double = 1
    /// Flush round in which this node was last evaluated.
    var evaluatedRound = -1
    /// Environment facts the commit record carries, read once per evaluation.
    var enabled = true
    var style = ResolvedStyle(font: nil, foreground: nil)
    /// Layout epoch in which this node's size cache was last cleared.
    var invalidatedEpoch = -1
    /// The layout-relevant content of the last evaluation.
    var layoutKey = LayoutKey.unset
    /// True from `setView` until the node is evaluated: its stored view is not the one it last expanded.
    var viewReplaced = false
    /// Identifies the environment this node's content sees: a fresh value whenever the node is the root or edits the environment, else its parent's. A child whose
    /// `inheritedStamp` differs from its parent's `envStamp` may see another environment and so cannot keep its body (`Graph.canKeepBody`).
    var envStamp = 0
    var inheritedStamp = -1
    /// Marked dirty because a ForEach data source it expands changed (`Graph.noteDataChange`), and/or for any other reason
    /// (`fullDirty`: its own observation fired, the root environment changed). Only a data-only mark may re-expand the node
    /// without re-evaluating its unchanged rows.
    var dataStale = false
    var fullDirty = false
    /// Evaluations so far; the data registrations of one evaluation share a token (see `Graph.trackData`).
    var evaluationCount = 0
    var dataEvalMark = -1
    var dataToken = 0
    var dataTether: Tether?
    /// Observation bookkeeping: the node's live tracking (if any) and which tracking is the current one.
    var tether: Tether?
    var trackToken = 0
    var trackingLive = false
    /// The focus storage the live tracking of a `.focused` modifier covers.
    var trackedFocusStorage: ObjectIdentifier?
    /// True while the node is listed in `Graph.animating`.
    var isAnimating = false
    var storage: [String: AnyObject] = [:]
    /// Preferences produced by this node's subtree, reduced in child order.
    var preferences = PreferenceValues()
    var hasPreferenceSource = false
    var alive = true
    var appeared = false
    /// Bumped on teardown and on task restart. Owner tokens captured before stop matching.
    var generation = 0
    var focused = false
    /// Set on a reinserted List row that held focus when removed; applied after its first evaluate.
    var restoreFocus = false
    var task: Task<Void, Never>?
    /// Id of the current `task(id:)` run, compared on re-evaluation.
    var taskID: AnyEquatable?
    /// Last value of `.animation(_:value:)`, compared on re-evaluation.
    var lastEquatable: AnyEquatable?
    /// Monotonic per-graph creation number. Unlike object addresses it is never reused.
    var instance = 0
    /// Layout target in logical points, set by the layout pass (snapped to the pixel grid).
    var frame: LayoutRect = .zero
    /// Text memo: measured sizes for the current text, keyed by wrap width (nil = no wrap).
    var memoText: String?
    var memo: [CGFloat?: LayoutSize] = [:]
    /// Cache owned by a custom `Layout` container.
    var layoutStorage: Any?
    /// Retired-row state, used only when this node retains removed row state (List).
    var rowCache = RowStateCache()
    /// Scroll offset of a ScrollView node, in logical points, clamped by the layout pass.
    var scrollOffset: CGFloat = 0
    /// Configured horizontal/vertical offsets; nil for legacy scroll nodes.
    var scrollOffsetX: CGFloat?
    var scrollOffsetY: CGFloat?
    /// Target opacity (own `.opacity` times the parent's target).
    var targetOpacity: Double = 1
    /// Presented (animated) values: what the last commit showed.
    var presentedFrame: LayoutRect = .zero
    var presentedOpacity: Double = 1
    /// False until the first commit presents this node.
    var committed = false
    /// Running interpolation of `presentedFrame` and `presentedOpacity`.
    var motion: MotionChain?
    /// Per-field text input state (TextField and TextEditor nodes only).
    var textInput: TextInputState?
    /// Font value of the last measurement (the memo is keyed by text, font metadata, line limit and width).
    var memoFont: Font?
    var memoLineLimit: Int?
    /// Selection binding of a List node, set at evaluation.
    var selection: SelectionAccess?
    /// Anchor and cursor of a List's keyboard and click selection, as row tags.
    var selectionAnchor: AnyHashable?
    var selectionCursor: AnyHashable?
    /// Items of a Menu or context menu, evaluated at each evaluation. Nil for other nodes.
    var menuEntries: [MenuEntry]?
    /// The presented alert or dialog, while presented. Nil otherwise.
    var presented: PresentedModel?

    init(id: NodeID, relative: [Segment], view: any View, info: ViewTypes.Info, parent: Node?) {
        self.id = id
        self.relative = relative
        self.view = view
        self.info = info
        self.parent = parent
        handle = NodeHandle()
        handle.node = self
    }

    /// The node's kind, derived from its view once per view assignment.
    var kind: NodeKind {
        resolveKind()
        return kindCache
    }

    /// What a primitive node expands to (its stored content), nil for a user view and for leaf primitives.
    var primitiveContent: (any View)? {
        resolveKind()
        return contentCache
    }

    private func resolveKind() {
        if kindResolved { return }
        if let read = info.readPrimitive {
            let read = read(view)
            kindCache = read.kind
            contentCache = read.content
        } else {
            kindCache = .user
            contentCache = nil
        }
        kindResolved = true
    }
    var depth: Int { id.segments.count }

    /// Cancels the node's live observation registration, if it has one.
    func retireTracking() {
        dataToken &+= 1
        dataTether?.version &+= 1
        guard trackingLive else { return }
        trackToken &+= 1
        trackingLive = false
        tether?.version &+= 1
    }

    /// Forgets the measured sizes of this node and every ancestor (their results depend on this subtree). Within one layout epoch
    /// the first call clears the whole chain, so a later call stops at the first ancestor already cleared.
    func invalidateLayout(epoch: Int) {
        var current: Node? = self
        while let node = current, node.invalidatedEpoch != epoch {
            node.invalidatedEpoch = epoch
            if !node.sizeCache.isEmpty { node.sizeCache.removeAll(keepingCapacity: true) }
            current = node.parent
        }
    }

    var retainsRemovedRowState: Bool {
        if case .stack(let spec) = kind { return spec.retainsRemovedRowState }
        return false
    }

    /// Drops everything the node owns, so that a removed node cannot keep its @State, environment,
    /// view values (and the closures in them) or observation state alive.
    func releaseContents() {
        children = []
        childNodes = []
        sizeCache = [:]
        storage = [:]
        environment = EnvironmentValues()
        inherited = EnvironmentValues()
        view = EmptyView()
        taskID = nil
        lastEquatable = nil
        layoutStorage = nil
        rowCache = RowStateCache()
        textInput = nil
        memo = [:]
        memoText = nil
        memoFont = nil
        selection = nil
        selectionAnchor = nil
        selectionCursor = nil
        menuEntries = nil
        presented = nil
        scrollOffsetX = nil
        scrollOffsetY = nil
    }
}

/// Keyed (ForEach) segment anywhere in a path.
private func hasKeyedSegment(_ segments: ArraySlice<Segment>) -> Bool {
    segments.contains { segment in
        if case .keyed = segment { return true }
        return false
    }
}

/// The part of a node's own content that its measured size depends on (children are tracked separately: a node that
/// re-evaluates with an unchanged key and unchanged children keeps its cached sizes).
enum LayoutKey: Equatable {
    /// A node that has not been evaluated yet.
    case unset
    /// No own content: a size comes from the children alone.
    case none
    /// A custom `Layout`, which can depend on anything its owner holds: never cached across evaluations.
    case always
    case text(String, String?)
    /// Text whose measurement depends on additive font metadata and/or line limit.
    case styledText(String, Font?, Int?)
    case stack(StackSpec)
    case padding(EdgeInsets)
    case frame(FrameSpec)
    case flexibleFrame(FlexibleFrameSpec)
    case spacer(CGFloat)
    case toggleLabelHidden
    case button(String?)
    case list(String?)
    case image(ImageSpec)
    case scrollView(ScrollViewConfiguration)
}

/// Guarded commit for async work started by `.task`. A commit is accepted only while the
/// owning node is alive and still has the generation the task was started under.
public struct TaskOwnerToken: Sendable {
    fileprivate let handle: NodeHandle
    fileprivate let generation: Int

    @MainActor
    public var isLive: Bool {
        guard let node = handle.node else { return false }
        return node.alive && node.generation == generation
    }

    @MainActor
    @discardableResult
    public func commit(_ body: @MainActor () -> Void) -> Bool {
        guard isLive else { return false }
        body()
        return true
    }
}

public enum TaskOwner {
    @TaskLocal public static var current: TaskOwnerToken?
}

// MARK: - Commit records

public struct ResolvedNode: Equatable, Sendable {
    public let id: String
    /// The node's creation number in its graph: unique, never reused, and unchanged while the node lives (a removed row that
    /// comes back is a new node with a new number). A backend keys its retained state by it instead of hashing `id`.
    public let instance: Int
    public let kind: String
    /// Text of a Text node, or the displayed text of a TextField (committed text plus marked text).
    public let text: String?
    /// Presented (animated) frame in logical points, edges snapped to the physical pixel grid.
    public let frame: LayoutRect
    /// The same frame in physical device pixels.
    public let pixelFrame: PixelRect
    /// Presented opacity in 0...1 (1 unless an opacity modifier or an insertion animation applies).
    public let opacity: Double
    /// TextField only: the caret or selection in displayed text.
    public let selection: UTF16Range?
    /// TextField only: the marked (composing) range in displayed text.
    public let marked: UTF16Range?
    public let children: [ResolvedNode]
    /// True for a labeled control whose label was hidden by `.labelsHidden()`; nil for other nodes.
    public let labelsHidden: Bool?
    /// Explicit Toggle style type metadata; nil when no `.toggleStyle` modifier applies.
    public let toggleStyle: String?
    /// TextField only: the `.textFieldStyle` type metadata; nil when none applies.
    public let fieldStyle: String?
    /// TextField only: the placeholder (the prompt, else the title), shown while the field is empty.
    public let placeholder: String?
    /// Role, label, value, enablement and selection for the accessibility backend.
    public let accessibility: ResolvedAccessibility
    /// Font and foreground colour in effect at this node (inherited through the environment).
    public let style: ResolvedStyle
    /// Image nodes only: the reference the backend loads.
    public let image: ImageReference?
    /// Image nodes only: resizing metadata for the backend.
    public let imageSizing: ResolvedImageSizing?
    /// Color views only: the resolved fill value; nil for existing node kinds.
    public let color: ResolvedColor?
    /// Shape nodes only: geometry and resolved paint, independent of any native renderer.
    fileprivate let shapeStorage: ResolvedShapeStorage?
    public var shape: ResolvedShape? { shapeStorage?.value }
    /// Menu and context-menu nodes only: the items, with disabled state and submenus.
    public let menu: [ResolvedMenuItem]?
    /// Alert and confirmation dialog nodes, while presented.
    public let presentation: ResolvedPresentation?
    /// Modifier nodes created by `.keyboardShortcut(_:modifiers:)`.
    public let shortcut: ResolvedShortcut?
    /// Button nodes only: the `.buttonStyle` type metadata; nil when none applies.
    public let buttonStyle: String?
    /// Button nodes only: true under `.keyboardShortcut(.defaultAction)` (Return, no modifiers), the window's default button.
    public let isDefaultButton: Bool
    /// List nodes only: the `.listStyle` type metadata; nil when none applies.
    public let listStyle: String?
}

extension ResolvedNode {
    /// The same node with a new frame, opacity and children (a removal transition presents a frozen subtree moved and faded).
    func replacing(frame: LayoutRect, pixelFrame: PixelRect, opacity: Double, children: [ResolvedNode]) -> ResolvedNode {
        ResolvedNode(id: id, instance: instance, kind: kind, text: text, frame: frame, pixelFrame: pixelFrame, opacity: opacity,
                     selection: selection, marked: marked, children: children, labelsHidden: labelsHidden, toggleStyle: toggleStyle,
                     fieldStyle: fieldStyle, placeholder: placeholder, accessibility: accessibility, style: style, image: image,
                     imageSizing: imageSizing, color: color, shapeStorage: shapeStorage, menu: menu, presentation: presentation, shortcut: shortcut,
                     buttonStyle: buttonStyle, isDefaultButton: isDefaultButton, listStyle: listStyle)
    }
}

/// Indirect immutable storage keeps optional shape metadata off every legacy snapshot.
fileprivate final class ResolvedShapeStorage: Equatable, Sendable {
    let value: ResolvedShape

    init(_ value: ResolvedShape) {
        self.value = value
    }

    static func == (lhs: ResolvedShapeStorage, rhs: ResolvedShapeStorage) -> Bool {
        lhs.value == rhs.value
    }
}

/// Accessibility as the runtime resolves it. Roles: window, button, text-field, text-area, checkbox, static-text,
/// image, list, list-item, menu, separator, scroll-area, alert, dialog (the first six are the CONTRACT canonical set).
public struct ResolvedAccessibility: Equatable, Sendable {
    public let role: String?
    public let label: String?
    /// Text for fields; "1" or "0" for a checkbox (Toggle).
    public let value: String?
    public let isEnabled: Bool
    /// True for a List row whose tag is in the selection.
    public let isSelected: Bool
}

public struct ResolvedStyle: Equatable, Sendable {
    public let font: Font?
    public let foreground: ResolvedColor?
    /// The colour scheme in effect at this node (`.environment(\.colorScheme, _)`, `.preferredColorScheme(_)`): a backend resolves semantic colours with it.
    public let colorScheme: ColorScheme

    public init(font: Font?, foreground: ResolvedColor?, colorScheme: ColorScheme = .light) {
        self.font = font; self.foreground = foreground; self.colorScheme = colorScheme
    }
}

public struct CommitRecord: Equatable, Sendable {
    public let sequence: Int
    /// Nil only in the final record emitted by `tearDown()`.
    public let root: ResolvedNode?
    public let focused: String?
    /// Animation names requested by transactions that contributed to this flush, joined by ",".
    public let animation: String?
}

// MARK: - Profile

/// Per-phase wall-clock counters of one graph (nanoseconds, from the monotonic clock). Off by default: a host or a benchmark
/// sets `Graph.profile` to a fresh value to start counting and reads it back to stop.
public struct GraphProfile: Sendable {
    /// `flush()` calls and commit records built.
    public var flushes = 0
    public var commits = 0
    /// Nodes whose body or primitive content was evaluated.
    public var evaluations = 0
    /// Dirty-node evaluation, layout pass, change detection, transaction application, record resolution, commit sink.
    public var evaluateNS: UInt64 = 0
    public var layoutNS: UInt64 = 0
    public var diffNS: UInt64 = 0
    public var transactionNS: UInt64 = 0
    public var resolveNS: UInt64 = 0
    public var sinkNS: UInt64 = 0
    /// Nodes in the live tree at the last commit and nodes resolved into records in total.
    public var liveNodes = 0
    public var resolvedNodes = 0
    public init() {}

    @inline(__always)
    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}

// MARK: - Graph

@MainActor
public final class Graph {
    struct Entry {
        let relative: [Segment]
        let view: any View
        let info: ViewTypes.Info
    }

    private(set) var root: Node?
    var nodes: [NodeID: Node] = [:]
    /// Live nodes by their string id (what hosts and tests address nodes by).
    private var nodesByString: [String: Node] = [:]
    /// Nodes that hold or recently held a running motion, in path order once `animatingNeedsSort` is cleared.
    var animating: [Node] = []
    /// onAppear actions of nodes that appeared in the running flush; `flush` runs them after presenting the state those nodes first appeared in.
    var pendingAppear: [() -> Void] = []
    /// Removed subtrees still presented while their removal transition runs (see Transition.swift).
    var ghosts: [Ghost] = []
    var animatingNeedsSort = false
    /// Bumped by each layout pass; see `Node.invalidateLayout(epoch:)`.
    private(set) var layoutEpoch = 0
    /// Counts evaluation rounds of a flush; see `Node.evaluatedRound`.
    private var evaluationRound = 0
    private var envStampCounter = 0
    /// `.preferredColorScheme` (ColorScheme.swift): the request made during this flush, and the root scheme before the first request.
    var windowSchemeRequest: PreferredSchemeRequest?
    var windowSchemeBase: ColorScheme?
    /// Turns on reduction only after a tree actually contains a preference source.
    private var preferenceReductionEnabled = false
    /// Live `.onPreferenceChange` nodes; legacy flushes skip observer traversal entirely.
    private var preferenceObserverNodes: Set<NodeID> = []
    /// Observation change callbacks received (tests check that retired registrations stay silent).
    private(set) var observationCallbacks = 0
    private var dirty: [NodeID: Node] = [:]
    private var flushScheduled = false
    private(set) var sequence = 0
    private var instanceCounter = 0
    /// Host-supplied time in seconds of the last `tick(now:)`; nil before the first tick. It has no required origin. A motion
    /// does not start at it: a motion begins at the next tick (see `advanceMotions`).
    var clock: Double?
    private var closed = false
    /// The focused node with the smallest id seen so far while resolving a record.
    private var resolveFocus: Node?
    let measurer: any TextMeasurer
    /// Physical pixels per logical point.
    let scale: CGFloat
    /// Size proposal for the root view. A host sets this to its content size.
    public var rootProposal: ProposedViewSize = .unspecified
    public var commitSink: ((CommitRecord) -> Void)?
    /// Intrinsic size of an image reference, in logical points. A host supplies the real size; the default is 24 pt.
    public var imageIntrinsicSize: (ImageReference) -> LayoutSize = { _ in LayoutSize(width: 24, height: 24) } {
        didSet { for node in nodes.values { node.sizeCache.removeAll() } }
    }
    /// Intrinsic size SwiftUI uses for `resizable().scaledToFit()/scaledToFill` of an image reference when it
    /// differs from the natural size above (SF Symbols fit by a larger default symbol size than their natural
    /// image size). Nil (the default) keeps the natural size.
    public var imageFitIntrinsicSize: (ImageReference) -> LayoutSize? = { _ in nil } {
        didSet { for node in nodes.values { node.sizeCache.removeAll() } }
    }
    /// Phase counters, nil (off) by default. See `GraphProfile`.
    public var profile: GraphProfile?
    /// Platform used to map native chords to logical commands (CONTRACT section 4).
    public var keyboardPlatform: KeyboardPlatform = .mac
    /// Models macOS System Settings > Keyboard > "Keyboard navigation" turned on: Tab also stops on focus-bound
    /// Buttons and Toggles. Default false (text fields and lists only). See FocusTraversal.swift.
    public var tabFocusesAllControls = false

    private static let rootTypeName = TypeName(Void.self, display: "Root")

    public init(_ rootView: some View, measurer: (any TextMeasurer)? = nil, scale: CGFloat = 1) {
        self.measurer = measurer ?? FixedAdvanceTextMeasurer()
        self.scale = scale
        let node = Node(id: NodeID(segments: [.type(Graph.rootTypeName)]), relative: [], view: rootView,
                        info: ViewTypes.info(for: rootView), parent: nil)
        node.instance = 0
        root = node
        nodes[node.id] = node
        nodesByString[node.idString] = node
        evaluate(node)
    }

    // MARK: Public test surface

    /// Sizes of every table and queue the graph keeps (R10 memory diagnosis). A table that grows without bound under a steady
    /// workload shows up here as a count that rises with time. Walks every live node: call it at a low rate.
    public struct Counts: Sendable {
        public var nodes = 0, nodesByString = 0, animating = 0, dirty = 0
        public var sizeCacheEntries = 0, memoEntries = 0, rowCacheEntries = 0, nodeStorageEntries = 0
        public var tasks = 0, tethers = 0, textInputs = 0, motions = 0
        public var observationCallbacks = 0
        public var viewTypeInfos = 0, queuedTransactions = 0, deferredCompletions = 0
        public init() {}
    }

    public func counts() -> Counts {
        var c = Counts()
        c.nodes = nodes.count
        c.nodesByString = nodesByString.count
        c.animating = animating.count
        c.dirty = dirty.count
        c.observationCallbacks = observationCallbacks
        for node in nodes.values {
            c.sizeCacheEntries += node.sizeCache.count
            c.memoEntries += node.memo.count
            c.rowCacheEntries += node.rowCache.entryCount
            c.nodeStorageEntries += node.storage.count
            if node.task != nil { c.tasks += 1 }
            if node.tether != nil || node.dataTether != nil { c.tethers += 1 }
            if node.textInput != nil { c.textInputs += 1 }
            if node.motion != nil { c.motions += 1 }
        }
        c.viewTypeInfos = ViewTypes.cacheCount
        c.queuedTransactions = TransactionContext.queuedCount
        c.deferredCompletions = TransactionContext.deferred.count
        return c
    }

    /// Applies pending invalidations (coalesced), lays out, and always emits one commit record.
    public func flush() {
        let flushStart = profile == nil ? 0 : GraphProfile.now()
        var rounds = 0
        var presentedBeforeAppear = false
        while rounds < 64 {
            while !dirty.isEmpty, rounds < 64 {
                rounds += 1
                evaluationRound += 1
                // Shallow nodes first so a dirty ancestor evaluates its dirty descendants; ties in creation order (deterministic and
                // an integer compare, where comparing path strings would cost more than evaluating a small node).
                let batch = dirty.values.sorted {
                    $0.depth != $1.depth ? $0.depth < $1.depth : $0.instance < $1.instance
                }
                dirty.removeAll()
                for node in batch where node.alive && nodes[node.id] === node {
                    // Evaluating a node re-evaluates everything below it, so a dirty node already reached from a dirty ancestor
                    // in this round is done.
                    if node.evaluatedRound == evaluationRound { continue }
                    // A node marked only because a ForEach data source it expands changed, and whose own view has not been
                    // replaced, expands the same ForEach again: its unchanged rows need no evaluation (see `expand`).
                    evaluate(node, refresh: node.dataStale && !node.fullDirty && !node.viewReplaced)
                }
            }
            if !preferenceObserverNodes.isEmpty { deliverPreferenceChanges() }
            applyWindowSchemeRequest()
            if dirty.isEmpty {
                if pendingAppear.isEmpty { break }
                // SwiftUI runs onAppear after the first render of the node, and what it changes is a second update (so `onAppear { withAnimation { ... } }`
                // animates from the state the view first appeared in). Present that state first, then run the actions.
                commit()
                presentedBeforeAppear = true
                let actions = pendingAppear
                pendingAppear = []
                for action in actions { action() }
                if dirty.isEmpty { break }
                presentedBeforeAppear = false
            }
        }
        if profile != nil {
            profile!.flushes += 1
            profile!.evaluateNS &+= GraphProfile.now() &- flushStart
        }
        if !presentedBeforeAppear { commit() }
    }

    public func snapshot() -> ResolvedNode? {
        root.map { resolve($0) }
    }

    /// Creation number of the live node at `id`. Equal numbers mean the same node instance;
    /// a removed-then-reinserted row gets a new number.
    public func nodeInstance(_ id: String) -> Int? {
        node(id)?.instance
    }

    public func ids(ofKind kind: String) -> [String] {
        var out: [String] = []
        func walk(_ node: ResolvedNode) {
            if node.kind == kind { out.append(node.id) }
            node.children.forEach(walk)
        }
        snapshot().map(walk)
        return out
    }

    /// Invokes a Button's action. Returns false when the id is not a live button.
    @discardableResult
    public func tapButton(_ id: String) -> Bool {
        guard let target = node(id), case .button(let action) = target.kind, target.environment.isEnabled else {
            return false
        }
        action()
        return true
    }

    /// Flips a live, enabled Toggle's binding. Returns false when the id is not a live enabled toggle.
    @discardableResult
    public func activateToggle(_ id: String) -> Bool {
        guard let target = node(id), case .toggle(let binding) = target.kind, target.environment.isEnabled else {
            return false
        }
        binding.wrappedValue.toggle()
        return true
    }

    /// The text input state of a live TextField, for routing IME and text-store calls to it.
    public func textInput(_ id: String) -> TextInputState? {
        node(id)?.textInput
    }

    /// Sets the vertical scroll offset of a live ScrollView. The next flush lays it out, and the
    /// offset is clamped to the content. Configured scroll views map this scalar to their enabled axis.
    public func scroll(_ id: String, to offset: CGFloat) {
        guard let node = node(id) else { return }
        node.scrollOffset = offset
        if case .scrollView(let configuration) = node.kind {
            if configuration.axes.contains(.vertical) {
                node.scrollOffsetY = offset
            } else if configuration.axes.contains(.horizontal) {
                node.scrollOffsetX = offset
            }
        }
    }

    /// Sets configured horizontal & vertical offsets. Each enabled axis is clamped during layout.
    public func scroll(_ id: String, to offset: LayoutPoint) {
        guard let node = node(id), case .scrollView(let configuration) = node.kind else { return }
        if configuration.axes.contains(.horizontal) { node.scrollOffsetX = offset.x }
        if configuration.axes.contains(.vertical) { node.scrollOffsetY = offset.y }
    }

    /// The last laid-out scroll offset of a live ScrollView.
    public func scrollOffset(_ id: String) -> CGFloat? {
        guard let node = node(id) else { return nil }
        guard case .scrollView(let configuration) = node.kind else { return node.scrollOffset }
        if configuration.axes.contains(.vertical) { return node.scrollOffsetY ?? 0 }
        if configuration.axes.contains(.horizontal) { return node.scrollOffsetX ?? 0 }
        return node.scrollOffset
    }

    /// Last laid-out offsets of a configured ScrollView, or nil for a legacy view.
    public func scrollOffsets(_ id: String) -> LayoutPoint? {
        guard let node = node(id), case .scrollView(let configuration) = node.kind else { return nil }
        return LayoutPoint(x: configuration.axes.contains(.horizontal) ? (node.scrollOffsetX ?? 0) : 0,
                           y: configuration.axes.contains(.vertical) ? (node.scrollOffsetY ?? 0) : 0)
    }

    /// Edits the root environment (for example a host feeds the OS reduce-motion setting) and
    /// re-evaluates the whole tree at the next flush.
    public func setRootEnvironment(_ update: (inout EnvironmentValues) -> Void) {
        guard let root else { return }
        var environment = root.inherited
        update(&environment)
        root.inherited = environment
        root.envStamp = 0
        root.fullDirty = true
        dirty[root.id] = root
    }

    /// Advances animations to `now` (host-supplied seconds, monotonic; any origin). A motion created since the last tick
    /// begins here (its progress 0). Emits one commit record when any animation was running, so the host can draw the
    /// interpolated values.
    public func tick(now: Double) {
        guard !closed, root != nil else { return }
        let wasAnimating = !ghosts.isEmpty || animating.contains { $0.motion != nil && $0.alive }
        clock = now
        advanceMotions(now: now, anchoring: true)
        if wasAnimating { emit(animationNames: []) }
        TransactionContext.drainDeferred()
    }

    /// Tears the whole tree down: disappear actions run, tasks are cancelled, running animations and
    /// text input state are dropped, and every node is released with its @State, environment and task
    /// handles. One final commit record with a nil root is emitted, then the commit sink is cleared.
    /// Afterwards the graph is closed: flush and tick commit nothing.
    public func tearDown() {
        guard let root, !closed else { return }
        teardown(root.id)
        self.root = nil
        for ghost in ghosts { finishChain(ghost.chain) }
        ghosts.removeAll()
        nodes.removeAll()
        nodesByString.removeAll()
        preferenceObserverNodes.removeAll()
        animating.removeAll()
        dirty.removeAll()
        for queued in TransactionContext.takeQueued() { queued.settleIfDone() }
        sequence += 1
        commitSink?(CommitRecord(sequence: sequence, root: nil, focused: nil, animation: nil))
        closed = true
        commitSink = nil
        TransactionContext.drainDeferred()
    }

    // MARK: Helpers

    func node(_ id: String) -> Node? {
        nodesByString[id]
    }

    /// Live nodes in a stable order (by path), so completion order does not depend on hashing.
    func orderedNodes() -> [Node] {
        nodes.values.sorted { $0.idString < $1.idString }
    }

    // MARK: Expansion and reconciliation

    /// Flattens `view` into node entries. `refreshable` turns false when a container met on the way cannot be re-expanded
    /// without re-evaluating its rows (`ViewContainer.supportsRefreshSkip`).
    private func expand(_ view: any View, prefix: [Segment], into out: inout [Entry], refreshable: inout Bool) {
        let info = ViewTypes.info(for: view)
        switch info.shape {
        case .empty:
            return
        case .container:
            guard let container = view as? any ViewContainer else { return }
            if !container.supportsRefreshSkip { refreshable = false }
            for (segment, part) in container.parts() {
                expand(part, prefix: prefix + [segment], into: &out, refreshable: &refreshable)
            }
        case .optional:
            if let child = (view as? any OptionalViewBox)?.wrappedView {
                expand(child, prefix: prefix + [.optional], into: &out, refreshable: &refreshable)
            }
        case .leaf:
            out.append(Entry(relative: prefix + [.type(info.name)], view: view, info: info))
        }
    }

    /// `keepExisting`: a child that survives is left as it is (not given the new view, not evaluated). Valid only when the
    /// parent re-expanded the same views it expanded before, which is the case for a data-only refresh of its ForEach: a row
    /// whose element changed is woken by its own observation of the row's box.
    private func reconcile(_ parent: Node, entries: [Entry], keepExisting: Bool = false, changedRows: Set<AnyHashable> = []) {
        // Fast path, the usual re-evaluation: the same children in the same order. No ids are built and nothing is hashed.
        if entries.count == parent.childNodes.count {
            var same = true
            for index in entries.indices where entries[index].relative != parent.childNodes[index].relative {
                same = false
                break
            }
            if same {
                for index in entries.indices {
                    if keepExisting, !isChangedRow(entries[index], changedRows) { continue }
                    refreshChild(parent.childNodes[index], with: entries[index].view, info: entries[index].info, from: parent)
                }
                return
            }
        }

        var order: [NodeID] = []
        var relatives: [[Segment]] = []
        var kept: [Entry] = []
        order.reserveCapacity(entries.count)
        var surviving = Set<NodeID>(minimumCapacity: entries.count)
        for entry in entries {
            let childID = NodeID(parent: parent.id, relative: entry.relative)
            if !surviving.insert(childID).inserted { continue }  // duplicate ForEach id: first wins
            order.append(childID)
            relatives.append(entry.relative)
            kept.append(entry)
        }
        for old in parent.children where !surviving.contains(old) {
            if let oldNode = nodes[old] { captureGhost(parent: parent, old: oldNode) }
            if parent.retainsRemovedRowState, hasKeyedSegment(old.segments.dropFirst(parent.id.segments.count)) {
                parent.rowCache.beginRetiring(old)
                teardown(old, retainingIn: (list: parent, top: old))
                parent.rowCache.trim()
            } else {
                teardown(old)
            }
        }
        parent.children = order
        parent.invalidateLayout(epoch: layoutEpoch)
        var live: [Node] = []
        live.reserveCapacity(order.count)
        for (index, childID) in order.enumerated() {
            let entry = kept[index]
            if let existing = nodes[childID] {
                if keepExisting, !isChangedRow(entry, changedRows) {
                    live.append(existing)
                } else {
                    live.append(existing)
                    refreshChild(existing, with: entry.view, info: entry.info, from: parent)
                }
            } else {
                let created = Node(id: childID, relative: relatives[index], view: entry.view, info: entry.info, parent: parent)
                instanceCounter += 1
                created.instance = instanceCounter
                inherit(created, from: parent)
                if let list = rowListAncestor(of: parent) {
                    if let restored = list.rowCache.take(childID) { created.storage = restored }
                    created.restoreFocus = list.rowCache.takeFocus(childID)
                }
                nodes[childID] = created
                nodesByString[created.idString] = created
                live.append(created)
                evaluate(created)
                if created.restoreFocus { restoreFocus(created) }
            }
        }
        parent.childNodes = live
    }

    /// True when `entry` is a ForEach row whose element is new or changed in the expansion being reconciled.
    private func isChangedRow(_ entry: Entry, _ changedRows: Set<AnyHashable>) -> Bool {
        if changedRows.isEmpty { return false }
        for segment in entry.relative {
            if case .keyed(let id) = segment, changedRows.contains(id) { return true }
        }
        return false
    }

    /// Hands the parent's environment, and the facts the commit record reads from it, to a child about to be evaluated.
    private func inherit(_ child: Node, from parent: Node) {
        child.inherited = parent.environment
        child.inheritedEnabled = parent.enabled
        child.inheritedStyle = parent.style
        child.inheritedStamp = parent.envStamp
    }

    /// Hands `child` its new view and evaluates it, unless SwiftUI would not run its body: a user view that is alive, clean, sees the same environment and whose new view value
    /// compares equal to the one it last evaluated keeps its body (its own observation still wakes it when a model it read changes).
    private func refreshChild(_ child: Node, with view: any View, info: ViewTypes.Info, from parent: Node) {
        if canKeepBody(child, newView: view, parent: parent) { return }
        child.setView(view, info: info)
        inherit(child, from: parent)
        evaluate(child)
    }

    private func canKeepBody(_ child: Node, newView: any View, parent: Node) -> Bool {
        guard child.alive, child.appeared, !child.viewReplaced, !child.fullDirty, !child.dataStale, child.inheritedStamp == parent.envStamp else { return false }
        guard case .user = child.kind else { return false }
        return ViewEquality.equal(child.view, newView)
    }

    /// Gives focus back to a reinserted node that held it when its List removed it.
    private func restoreFocus(_ node: Node) {
        node.restoreFocus = false
        guard case .modifier(.focus(let link)) = node.kind else { return }
        link.focus()
        node.focused = true
    }

    /// The nearest ancestor-or-self that retains removed row state.
    private func rowListAncestor(of node: Node) -> Node? {
        var current: Node? = node
        while let candidate = current {
            if candidate.retainsRemovedRowState { return candidate }
            current = candidate.parent
        }
        return nil
    }

    /// Tears a node down, in order: onDisappear, task cancel, motion and focus release, then the
    /// children. When `retainingIn` is set, the node's `@State` storage and focus are kept in that
    /// List's row cache under its node id, so a reinsertion can restore them.
    private func teardown(_ id: NodeID, retainingIn target: (list: Node, top: NodeID)? = nil) {
        guard let node = nodes.removeValue(forKey: id) else { return }
        if !preferenceObserverNodes.isEmpty { preferenceObserverNodes.remove(id) }
        if nodesByString[node.idString] === node { nodesByString[node.idString] = nil }
        node.alive = false
        node.generation += 1
        node.retireTracking()
        dirty[id] = nil
        if node.appeared {
            node.appeared = false
            if case .modifier(.disappear(let action)) = node.kind { action() }
        }
        node.task?.cancel()
        node.task = nil
        endMotion(node)
        var wasFocused = false
        if node.focused, case .modifier(.focus(let link)) = node.kind {
            wasFocused = true
            node.focused = false
            link.release()
        }
        if let target, !node.storage.isEmpty || wasFocused {
            target.list.rowCache.retain(id, top: target.top, state: node.storage, wasFocused: wasFocused)
        }
        for child in node.children { teardown(child, retainingIn: target) }
        node.releaseContents()
    }

    /// One evaluation of an `.onChange(of:)` node. The previous value lives in `node.storage` (key `onChangeKey`), the same
    /// store as the node's `@State`: a List row that is removed and reinserted gets its storage back (`RowStateCache`), so the
    /// reinserted node compares the new value with the last value the preserved view saw, as macOS 27 SwiftUI does
    /// (SR0-O F3: the preserved row saw `Row 4x`, the reinsertion brings `Row 4`, the action runs once more). A node with no
    /// stored baseline (first appearance, or any VStack / LazyVStack row, whose storage is not kept) only records one.
    private func runOnChange(_ node: Node, value: AnyEquatable, initial: Bool, action: @escaping (Any, Any) -> Void) {
        // While an onAppear of this flush is still waiting (see `pendingAppear`), an action that follows it in evaluation order waits behind it.
        func run(_ old: Any, _ new: Any) {
            if pendingAppear.isEmpty { action(old, new) } else { pendingAppear.append { action(old, new) } }
        }
        if let baseline = node.storage[onChangeKey] as? OnChangeBaseline {
            let previous = baseline.value
            if !previous.matches(value.value) {
                baseline.value = value
                run(previous.value, value.value)
            }
        } else {
            node.storage[onChangeKey] = OnChangeBaseline(value)
            if initial { run(value.value, value.value) }
        }
    }

    private func deliverPreferenceChanges() {
        guard let root else { return }
        func visit(_ node: Node) {
            if case .modifier(.onPreferenceChange(let observer)) = node.kind {
                let value = observer.value(node.preferences)
                if let baseline = node.storage[onPreferenceChangeKey] as? PreferenceObserverBaseline,
                   baseline.key == observer.key {
                    if !observer.equals(baseline.value, value) {
                        baseline.value = value
                        observer.action(value)
                    }
                } else {
                    node.storage[onPreferenceChangeKey] = PreferenceObserverBaseline(key: observer.key, value: value)
                    // SwiftUI reports the first reduced value even when it equals the key's default (macOS 27, measured: a tree without
                    // contributors still calls the action once with defaultValue).
                    observer.action(value)
                }
            }
            for child in node.childNodes { visit(child) }
        }
        visit(root)
    }

    @discardableResult
    private func reducePreferences(_ node: Node) -> Bool {
        let hadSource = node.hasPreferenceSource
        var values = PreferenceValues()
        for child in node.childNodes { values.merge(child.preferences) }
        let ownSource: Bool
        if case .modifier(.preference(let contribution)) = node.kind {
            contribution.apply(&values)
            ownSource = true
        } else {
            ownSource = false
        }
        node.preferences = values
        node.hasPreferenceSource = ownSource || node.childNodes.contains(where: \.hasPreferenceSource)
        return hadSource || node.hasPreferenceSource
    }

    private func reducePreferencesUpward(from node: Node) {
        guard preferenceReductionEnabled else { return }
        var current: Node? = node
        while let ancestor = current {
            guard reducePreferences(ancestor) else { break }
            current = ancestor.parent
        }
    }

    private func runAppear(_ node: Node) {
        guard case .modifier(let spec) = node.kind else { return }
        switch spec {
        case .appear(let action):
            pendingAppear.append(action)
        case .task(let priority, let id, let action):
            node.taskID = id
            startTask(node, priority, action)
        default:
            break
        }
    }

    /// Starts (or restarts) a task for `node`. The previous run is cancelled, and its owner token
    /// stops matching, so a late commit from it is rejected.
    private func startTask(_ node: Node, _ priority: TaskPriority, _ action: @escaping @isolated(any) () async -> Void) {
        node.task?.cancel()
        node.generation += 1
        let token = TaskOwnerToken(handle: node.handle, generation: node.generation)
        node.task = Task(priority: priority) {
            await TaskOwner.$current.withValue(token) {
                await action()
            }
        }
    }

    private func bindDynamicProperties(_ node: Node) {
        // Reflection is needed only for view types that declare a dynamic property (decided once per type).
        guard node.info.hasDynamicProperties else { return }
        for child in Mirror(reflecting: node.view).children {
            if let key = child.label, let property = child.value as? DynamicPropertyStorage {
                property.bindDynamicProperty(to: node, key: key)
            }
        }
    }

    func textInputState(for node: Node, binding: Binding<String>, multiline: Bool) -> TextInputState {
        if let state = node.textInput {
            state.binding = binding
            state.adoptExternalText()
            return state
        }
        let state = TextInputState(binding: binding, multiline: multiline)
        node.textInput = state
        return state
    }

    /// Evaluates one node: applies its environment override, runs appear once, restarts a
    /// `task(id:)` whose id changed, reads its dependencies under observation tracking, then
    /// reconciles its children.
    func evaluate(_ node: Node, refresh: Bool = false) {
        guard node.alive else { return }
        if profile != nil { profile!.evaluations += 1 }
        node.evaluatedRound = evaluationRound
        node.evaluationCount &+= 1
        dirty[node.id] = nil
        node.viewReplaced = false
        node.dataStale = false
        node.fullDirty = false
        node.environment = node.inherited
        let kind = node.kind
        if case .modifier(.preference) = kind { preferenceReductionEnabled = true }
        if case .modifier(.onPreferenceChange) = kind {
            preferenceObserverNodes.insert(node.id)
        } else if !preferenceObserverNodes.isEmpty {
            preferenceObserverNodes.remove(node.id)
        }
        if case .modifier(.environment(let apply)) = kind {
            apply(&node.environment)
            noteWindowSchemeRequest(node)
        }
        if node.parent == nil || kind.changesEnvironment {
            // An environment modifier re-applies its closure on every evaluation (its result cannot be compared), so its content always sees "another" environment; the root
            // only when its environment was edited (`setRootEnvironment` zeroes the stamp).
            if kind.changesEnvironment || node.envStamp == 0 {
                envStampCounter &+= 1
                node.envStamp = envStampCounter
            }
            node.enabled = node.environment.isEnabled
            node.style = ResolvedStyle(font: node.environment.font, foreground: node.environment.foregroundStyle, colorScheme: node.environment.colorScheme)
        } else {
            node.envStamp = node.parent?.envStamp ?? 0
            node.enabled = node.inheritedEnabled
            node.style = node.inheritedStyle
        }
        if !node.appeared {
            node.appeared = true
            runAppear(node)
        } else if case .modifier(.task(let priority, let id?, let action)) = kind,
                  let previous = node.taskID, !previous.matches(id.value) {
            node.taskID = id
            startTask(node, priority, action)
        }
        if case .modifier(.animation(let value, let animation)) = kind {
            if let previous = node.lastEquatable, !previous.matches(value.value) {
                TransactionContext.enqueue(AnimationTransaction(animation: animation, completion: nil, scope: node))
            }
            node.lastEquatable = value
        }
        if case .modifier(.onChange(let value, let initial, let action)) = kind {
            runOnChange(node, value: value, initial: initial, action: action)
        }
        if case .user = kind { bindDynamicProperties(node) }
        if case .stack = kind {
            node.selection = (node.view as? SelectionProviding)?.selectionAccess
        } else if node.selection != nil {
            node.selection = nil
        }
        if case .textField(let binding) = kind {
            _ = textInputState(for: node, binding: binding, multiline: false)
        }
        if case .textEditor(let binding) = kind {
            _ = textInputState(for: node, binding: binding, multiline: true)
        }
        noteLayoutContent(node, kind)

        // Only nodes whose content reads observable state register a dependency; a primitive that just hands back stored
        // children (Text, stacks, most modifiers) reads nothing, so it needs no tracking scope.
        let produced: (any View)?
        if case .modifier(.focus(let link)) = kind, node.trackingLive, node.trackedFocusStorage == link.storage {
            // The only observable thing a `.focused` modifier reads is the focus storage, and the live registration already
            // covers that same storage: read the value without registering a second time.
            noteFocus(node, link.isFocused())
            produced = node.primitiveContent
        } else if tracksDependencies(kind, node) {
            node.retireTracking()
            if case .modifier(.focus(let link)) = kind { node.trackedFocusStorage = link.storage }
            node.trackToken &+= 1
            let token = node.trackToken
            let tether = node.tether ?? Tether()
            node.tether = tether
            node.trackingLive = true
            produced = withObservationTracking({
                _ = tether.version
                ObservationScope.depth += 1
                defer { ObservationScope.depth -= 1 }
                return produceContent(node, kind)
            }, onChange: { [weak self, handle = node.handle] in
                // Weak on purpose: a pending observation must not keep the graph or its nodes alive. A registration that was
                // retired by a newer evaluation reports nothing.
                MainActor.assumeIsolated {
                    self?.observationCallbacks += 1
                    guard let node = handle.node, node.trackToken == token else { return }
                    node.trackingLive = false
                    self?.noteChange(node)
                }
            })
        } else {
            produced = node.primitiveContent
        }

        guard let produced else {
            reconcile(node, entries: [])
            reducePreferencesUpward(from: node)
            return
        }
        let producedInfo = ViewTypes.info(for: produced)
        if producedInfo.shape == .leaf {
            // One view that is a node itself (a modifier's content, a user view's body): update that child in place with no
            // entry list and no id built.
            if node.childNodes.count == 1, node.childNodes[0].relative.count == 1,
               case .type(let name) = node.childNodes[0].relative[0], name === producedInfo.name {
                refreshChild(node.childNodes[0], with: produced, info: producedInfo, from: node)
            } else {
                reconcile(node, entries: [Entry(relative: [.type(producedInfo.name)], view: produced, info: producedInfo)])
            }
            reducePreferencesUpward(from: node)
            return
        }
        var entries: [Entry] = []
        var refreshable = true
        let outer = ExpansionContext.owner
        ExpansionContext.owner = (self, node)
        ExpansionContext.changedRows = []
        expand(produced, prefix: [], into: &entries, refreshable: &refreshable)
        ExpansionContext.owner = outer
        let changedRows = ExpansionContext.changedRows
        ExpansionContext.changedRows = []
        // Only a node that hands back its stored content expands the same views as last time; a body re-runs and builds new ones.
        reconcile(node, entries: entries, keepExisting: refresh && refreshable && !tracksDependencies(kind, node),
                  changedRows: changedRows)
        reducePreferencesUpward(from: node)
    }

    /// Drops the cached sizes of this node and its ancestors when the node's own layout-relevant content changed.
    private func noteLayoutContent(_ node: Node, _ kind: NodeKind) {
        let key: LayoutKey
        switch kind {
        case .text(let string):
            let font = node.environment.font
            let lineLimit = node.environment.lineLimit
            key = font?.metadata == nil && lineLimit == nil
                ? .text(string, font?.id)
                : .styledText(string, font, lineLimit)
        case .textField, .textEditor:
            let font = node.environment.font
            let string = node.textInput?.display ?? ""
            key = font?.metadata == nil ? .text(string, font?.id) : .styledText(string, font, nil)
        case .stack(let spec) where spec.name == "List": key = .list(node.environment.listStyleMetadata)
        case .stack(let spec): key = .stack(spec)
        case .modifier(.padding(let insets)): key = .padding(insets)
        case .modifier(.frame(let frame)): key = .frame(frame)
        case .modifier(.flexibleFrame(let frame)): key = .flexibleFrame(frame)
        case .spacer(let length): key = .spacer(length)
        case .toggle where node.environment.labelsHidden: key = .toggleLabelHidden
        case .toggle: key = .none
        case .button: key = .button(node.environment.buttonStyleMetadata)
        case .image(let spec): key = .image(spec)
        case .scrollView(let configuration): key = .scrollView(configuration)
        case .layout: key = .always
        default: key = .none
        }
        if key == .always || key != node.layoutKey {
            node.layoutKey = key
            node.invalidateLayout(epoch: layoutEpoch)
        }
    }

    /// True for the kinds whose content evaluation reads observable state.
    private func tracksDependencies(_ kind: NodeKind, _ node: Node) -> Bool {
        if node.selection != nil { return true }
        switch kind {
        case .user, .textField, .textEditor, .toggle, .menu: return true
        case .modifier(.focus), .modifier(.presentation), .modifier(.contextMenu): return true
        default: return false
        }
    }

    /// Reads the node's dependencies and returns the view it expands to. Runs inside the observation tracking scope.
    private func produceContent(_ node: Node, _ kind: NodeKind) -> (any View)? {
        switch kind {
        case .textField, .textEditor: _ = node.textInput?.display
        case .modifier(.focus(let link)): noteFocus(node, link.isFocused())
        case .toggle(let binding): _ = binding.wrappedValue
        case .modifier(.presentation(let payload)):
            node.presented = payload.isPresented.wrappedValue
                ? PresentedModel(payload: payload, environment: node.environment)
                : nil
        case .modifier(.contextMenu(let content)):
            node.menuEntries = ViewWalk.entries(content, environment: node.environment)
        case .menu:
            node.menuEntries = (node.view as? MenuView).map {
                ViewWalk.entries($0.menuContent, environment: node.environment)
            }
        default: break
        }
        if let selection = node.selection { _ = selection.current() }
        if case .user = kind { return node.view.evaluateBody() }
        return node.primitiveContent
    }

    // MARK: Invalidation

    func noteChange(_ node: Node) {
        guard node.alive, nodes[node.id] === node else { return }
        node.fullDirty = true
        dirty[node.id] = node
        scheduleFlush()
    }

    /// A ForEach data source that `node` expands changed. The node is re-expanded at the next flush.
    func noteDataChange(_ node: Node) {
        guard node.alive, nodes[node.id] === node else { return }
        node.dataStale = true
        dirty[node.id] = node
        scheduleFlush()
    }

    /// Reads a ForEach's data on behalf of `node`, the node that expands it. The registration is the node's own and is kept apart
    /// from the tracking of its content, so a change to the data re-expands the node (`noteDataChange`) without counting as a
    /// change of anything its content read. The registrations of one evaluation share a token; a newer evaluation supersedes them
    /// (its first read bumps the tether, which fires and so cancels the earlier ones).
    func trackData<T>(of node: Node, _ read: () -> T) -> T {
        if node.dataEvalMark != node.evaluationCount {
            node.dataEvalMark = node.evaluationCount
            node.dataToken &+= 1
            node.dataTether?.version &+= 1
        }
        let token = node.dataToken
        let tether = node.dataTether ?? Tether()
        node.dataTether = tether
        return withObservationTracking({
            _ = tether.version
            return read()
        }, onChange: { [weak self, handle = node.handle] in
            MainActor.assumeIsolated {
                guard let node = handle.node, node.dataToken == token else { return }
                self?.noteDataChange(node)
            }
        })
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            if !self.dirty.isEmpty { self.flush() }
        }
    }

    // MARK: Commit

    private func commit() {
        guard !closed, let root else { return }
        let profiling = profile != nil
        var t0 = profiling ? GraphProfile.now() : 0
        func lap(_ add: inout UInt64) {
            guard profiling else { return }
            let t1 = GraphProfile.now()
            add &+= t1 &- t0
            t0 = t1
        }
        if let clock { advanceMotions(now: clock, anchoring: false) }
        if profiling { lap(&profile!.transactionNS) }
        layoutRoot()
        assignOpacity(root, parent: 1)
        layoutEpoch += 1
        if profiling { lap(&profile!.layoutNS) }
        var changed: [Node] = []
        collectChanged(root, into: &changed)
        let transactions = TransactionContext.takeQueued()
        // Motions end in path order (completion order must not depend on how the tree was walked), so sort when a motion
        // can start or end in this commit.
        if !transactions.isEmpty || changed.contains(where: { $0.motion != nil }) {
            changed.sort { $0.idString < $1.idString }
        }
        if profiling { lap(&profile!.diffNS) }
        applyTransactions(transactions, changed: changed)
        if profiling { lap(&profile!.transactionNS) }
        emit(animationNames: transactions.compactMap { $0.animation?.name })
        TransactionContext.drainDeferred()
    }

    /// Collects the nodes whose layout target (frame or target opacity) differs from the previous commit's, and records the
    /// new targets as the baseline for the next.
    private func collectChanged(_ node: Node, into out: inout [Node]) {
        if node.frame != node.snapFrame || node.targetOpacity != node.snapOpacity {
            out.append(node)
            node.snapFrame = node.frame
            node.snapOpacity = node.targetOpacity
        }
        for child in node.childNodes { collectChanged(child, into: &out) }
    }

    /// Builds and delivers one commit record from the presented values.
    private func emit(animationNames: [String]) {
        guard let root else { return }
        let profiling = profile != nil
        let t0 = profiling ? GraphProfile.now() : 0
        sequence += 1
        resolveFocus = nil
        let resolved = resolve(root)
        let record = CommitRecord(
            sequence: sequence,
            root: resolved,
            focused: resolveFocus?.idString,
            animation: animationNames.isEmpty ? nil : animationNames.joined(separator: ",")
        )
        resolveFocus = nil
        let t1 = profiling ? GraphProfile.now() : 0
        commitSink?(record)
        if profiling {
            profile!.commits += 1
            profile!.liveNodes = nodes.count
            profile!.resolveNS &+= t1 &- t0
            profile!.sinkNS &+= GraphProfile.now() &- t1
        }
    }

    func resolve(_ node: Node, selected: Bool = false) -> ResolvedNode {
        let kind = node.kind
        let text: String?
        var selection: UTF16Range?
        var marked: UTF16Range?
        switch kind {
        case .text(let string):
            text = string
        case .textField, .textEditor:
            text = node.textInput?.display
            selection = node.textInput?.selection
            marked = node.textInput?.markedRange
        default:
            text = nil
        }
        if node.focused, node.alive, resolveFocus.map({ node.idString < $0.idString }) ?? true { resolveFocus = node }
        let hasSelection = node.selection != nil
        let selectedTags = node.selection?.current() ?? []
        let childNodes: [Node]
        if case .toggle = kind, node.environment.labelsHidden {
            childNodes = []
        } else {
            childNodes = node.childNodes
        }
        var children: [ResolvedNode] = []
        children.reserveCapacity(childNodes.count)
        for child in childNodes {
            let isSelected = hasSelection && (tagOf(child).map { selectedTags.contains($0) } ?? false)
            children.append(resolve(child, selected: isSelected))
        }
        if !ghosts.isEmpty {
            let id = node.idString
            for ghost in ghosts where ghost.parentID == id { children.insert(resolvedGhost(ghost), at: min(ghost.index, children.count)) }
        }
        var image: ImageReference?
        var imageSizing: ResolvedImageSizing?
        if case .image(let spec) = kind {
            image = spec.reference
            if spec.sizing.isResizable || spec.sizing.scalesToFit {
                imageSizing = spec.sizing
            }
        }
        var color: ResolvedColor?
        if case .color(let resolved) = kind { color = resolved }
        var shape: ResolvedShape?
        if case .shape(let resolvedShape) = kind { shape = resolvedShape }
        let labelsHidden: Bool?
        switch kind {
        case .toggle, .textField:
            labelsHidden = node.environment.labelsHidden ? true : nil
        default:
            labelsHidden = nil
        }
        let toggleStyle: String?
        if case .toggle = kind { toggleStyle = node.environment.toggleStyleMetadata }
        else { toggleStyle = nil }
        var fieldStyle: String?
        var placeholder: String?
        if case .textField = kind {
            fieldStyle = node.environment.textFieldStyleMetadata
            placeholder = placeholderOf(node)
        }
        var buttonStyle: String?
        var isDefaultButton = false
        if case .button = kind {
            buttonStyle = node.environment.buttonStyleMetadata
            var ancestor = node.parent
            while let a = ancestor, !isDefaultButton {
                if case .modifier(.keyboardShortcut(let key, let modifiers)) = a.kind, KeyboardShortcut(key, modifiers: modifiers).isDefaultAction { isDefaultButton = true }
                ancestor = a.parent
            }
        }
        var listStyle: String?
        if case .stack(let spec) = kind, spec.name == "List" { listStyle = node.environment.listStyleMetadata }
        var shortcut: ResolvedShortcut?
        if case .modifier(.keyboardShortcut(let key, let modifiers)) = kind {
            shortcut = ResolvedShortcut(
                chord: KeyboardChord(key: key, modifiers: modifiers),
                logical: KeyboardChords.command(for: key, modifiers: modifiers, on: keyboardPlatform)
            )
        }
        return ResolvedNode(
            id: node.idString,
            instance: node.instance,
            kind: kindName(node),
            text: text,
            frame: node.presentedFrame,
            pixelFrame: pixelRect(node.presentedFrame, scale: scale),
            opacity: node.presentedOpacity,
            selection: selection,
            marked: marked,
            children: children,
            labelsHidden: labelsHidden,
            toggleStyle: toggleStyle,
            fieldStyle: fieldStyle,
            placeholder: placeholder,
            accessibility: accessibility(of: node, children: children, selected: selected),
            style: node.style,
            image: image,
            imageSizing: imageSizing,
            color: color,
            shapeStorage: shape.map(ResolvedShapeStorage.init),
            menu: node.menuEntries.map(resolveMenu),
            presentation: node.presented.map(resolvePresentation),
            shortcut: shortcut,
            buttonStyle: buttonStyle,
            isDefaultButton: isDefaultButton,
            listStyle: listStyle
        )
    }

    /// Role, label and value for the accessibility backend. A primitive sets the role; a List's direct children
    /// are list items; an accessibilityLabel modifier overrides the label of its own node.
    private func accessibility(of node: Node, children: [ResolvedNode], selected: Bool) -> ResolvedAccessibility {
        var role: String?
        var label: String?
        var value: String?
        switch node.kind {
        case .text(let string):
            role = "static-text"
            label = string
        case .button:
            role = "button"
            label = joinedText(children)
        case .textField:
            role = "text-field"
            label = titleOf(node)
            value = node.textInput?.display
        case .textEditor:
            role = "text-area"
            value = node.textInput?.display
        case .toggle(let binding):
            role = "checkbox"
            label = titleOf(node) ?? joinedText(children)
            value = binding.wrappedValue ? "1" : "0"
        case .image(let spec):
            role = "image"
            label = spec.reference.name
        case .menu:
            role = "menu"
            label = joinedText(children)
        case .divider:
            role = "separator"
        case .scroll, .scrollView:
            role = "scroll-area"
        case .stack(let spec) where spec.name == "List":
            role = "list"
        case .modifier(.accessibilityLabel(let override)):
            label = override
        case .modifier(.presentation):
            if let presented = node.presented {
                role = presented.kind == .alert ? "alert" : "dialog"
                label = presented.title
            }
        default:
            break
        }
        if let parent = node.parent, case .stack(let spec) = parent.kind, spec.name == "List" {
            role = "list-item"
            label = label ?? joinedText(children)
        }
        return ResolvedAccessibility(
            role: role,
            label: label,
            value: value,
            isEnabled: node.enabled,
            isSelected: selected
        )
    }

    /// Accessibility title of a labelled control (TextField, Toggle), from its label view.
    private func titleOf(_ node: Node) -> String? {
        guard let labeled = node.view as? LabeledControl else { return nil }
        let title = ViewWalk.plainText(labeled.titleView)
        return title.isEmpty ? nil : title
    }

    /// A TextField's placeholder: its prompt, else its title.
    func placeholderOf(_ node: Node) -> String? {
        guard let view = node.view as? PlaceholderControl else { return nil }
        let text = ViewWalk.plainText(view.placeholderView)
        return text.isEmpty ? nil : text
    }

    /// The text of the resolved descendants, in order, joined by spaces. Nil when there is none.
    private func joinedText(_ resolved: [ResolvedNode]) -> String? {
        var parts: [String] = []
        func collect(_ item: ResolvedNode) {
            if let text = item.text, !text.isEmpty { parts.append(text) }
            item.children.forEach(collect)
        }
        resolved.forEach(collect)
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func kindName(_ node: Node) -> String {
        switch node.kind {
        case .user: return node.info.name.short
        case .text: return "Text"
        case .spacer: return "Spacer"
        case .button: return "Button"
        case .textField: return "TextField"
        case .stack(let spec): return spec.name
        case .layout: return "Layout"
        case .scroll, .scrollView: return "ScrollView"
        case .modifier(let spec): return spec.kindName
        case .toggle: return "Toggle"
        case .image: return "Image"
        case .color: return "Color"
        case .shape(let shape):
            switch shape.geometry {
            case .rectangle: return "Rectangle"
            case .roundedRectangle: return "RoundedRectangle"
            case .circle: return "Circle"
            }
        case .textEditor: return "TextEditor"
        case .divider: return "Divider"
        case .menu: return "Menu"
        }
    }
}
