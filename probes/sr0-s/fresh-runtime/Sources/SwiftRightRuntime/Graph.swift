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
    case identified(AnyHashable) // `.id(_:)`: a different value is a different view (state is not carried over)
    case erased              // AnyView / ViewModifier content: the erased view's own type names the next segment

    var description: String {
        switch self {
        case .type(let name): return name.short
        case .index(let i): return "#\(i)"
        case .branch(let i): return "branch\(i)"
        case .optional: return "opt"
        case .keyed(let value): return "[\(value)]"
        case .identified(let value): return "id(\(value))"
        case .erased: return "any"
        }
    }

    static func == (lhs: Segment, rhs: Segment) -> Bool {
        switch (lhs, rhs) {
        case (.type(let a), .type(let b)): return a === b
        case (.index(let a), .index(let b)): return a == b
        case (.branch(let a), .branch(let b)): return a == b
        case (.optional, .optional): return true
        case (.keyed(let a), .keyed(let b)): return a == b
        case (.identified(let a), .identified(let b)): return a == b
        case (.erased, .erased): return true
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
        case .identified(let value): return value.hashValue &+ 0x4_0000_000b
        case .erased: return 0x5_0000_000d
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
        /// True for a `GeometryReader`: the node builds its content from the size layout gives it (R1, #36).
        var isGeometryReader = false
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
        var info = Info(name: TypeName(type), shape: shape, hasDynamicProperties: dynamic, readPrimitive: reader)
        info.isGeometryReader = view is any GeometryReading
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
    /// SR1 round 5 (block swiftui.accessibility): the other accessibility modifiers. They are read by the host, which applies them to the element beneath.
    case accessibilityValue(String)
    case accessibilityHint(String)
    case accessibilityHidden(Bool)
    case accessibilityElement(AccessibilityChildBehavior)
    /// `accessibilityAddTraits` (add == true) and `accessibilityRemoveTraits`.
    case accessibilityTraits(AccessibilityTraits, add: Bool)
    /// SR1 round 5 (block swiftui.layout-priority): `.layoutPriority(_:)`, read by the stack that lays out this view (through wrappers that pass their child through).
    case layoutPriority(Double)
    /// SR1 round 5 (layout rules, decision L7): `.fixedSize(horizontal:vertical:)`: the child is proposed nothing (its ideal size) on each fixed axis and the view reports what the child reports.
    case fixedSize(horizontal: Bool, vertical: Bool)
    /// SR1 round 4 (block swiftui.list-row-style): `.listRowSeparator(_:)` and `.listRowBackground(_:)`, read by the host from the row's subtree.
    case listRowSeparator(Visibility)
    case listRowBackground(ListRowBackground)
    /// SR1 wave 1 block I2: `.clipped()`. Geometry passes through; the host clips the subtree's painting to this node's frame.
    case clipped
    /// F-path (#35): `.rotationEffect(_:anchor:)`. Geometry passes through (layout is unchanged); the host rotates the shape leaves of the subtree about the anchor of this node's frame.
    case rotation(Angle, UnitPoint)
    /// SR2 R4 (#39): `.scaleEffect(x:y:anchor:)`. Layout is unchanged; the host scales the subtree's painting about the anchor of this node's frame.
    /// The factors are animated like a frame (`Node.presentedScale`).
    case scale(CGFloat, CGFloat, UnitPoint)
    /// SR2 R4 (#39): `.brightness(_:)`. Layout is unchanged; the host adds the amount to each sRGB channel of the subtree's colours (clamped).
    case brightness(Double)
    /// SR2 R6 (#41): `.clipShape(_:style:)`. Layout is unchanged; the host clips the subtree's painting to the shape in this node's frame. The geometry is
    /// animated like a shape's (`Node.presentedGeometry`), so an animatable clip follows its shape.
    case clipShape(ShapeGeometry, FillStyle)
    /// SR1 round 6 block 38: `.onHover(perform:)` and `.onTapGesture(count:perform:)`; the host routes pointer positions to `Graph.pointerMoved` and a release to `Graph.tapGesture`.
    case hover(HoverHook)
    case tap(TapHook)
    /// SR2 R1 (#36): `.offset(x:y:)`. Layout is unchanged; the child is placed shifted by (x, y) (not mirrored under right-to-left, as in SwiftUI).
    case offset(CGFloat, CGFloat)
    /// SR2 R1 (#36): `.position(x:y:)`. Takes the whole proposed space; the child is centred at the point in this node's coordinate space.
    case position(CGFloat, CGFloat)
    /// Issue #68: `.alignmentGuide(_:computeValue:)`. Layout of the view itself is unchanged; the stack, ZStack or overlay that aligns on the guide reads the value.
    case alignmentGuide(AlignmentGuideSpec)
    /// Issue #68: `.gridColumnAlignment(_:)`, read by the enclosing Grid from the cell (through wrappers that pass their child through).
    case gridCell(GridCellSpec)
    /// Issue #60 (pass 2): the indeterminate `ProgressView` spinner. Layout passes through; the node resolves a rotation of `step / steps` of a turn about the centre, where `step` is
    /// the whole number of `period / steps` intervals of the host clock that have elapsed (`Graph.tick` commits whenever the step changes). A repeat-forever driver for this control only.
    case spinner(steps: Int, period: Double)

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
        case .accessibilityValue: return "modifier.accessibilityValue"
        case .accessibilityHint: return "modifier.accessibilityHint"
        case .accessibilityHidden: return "modifier.accessibilityHidden"
        case .accessibilityElement: return "modifier.accessibilityElement"
        case .accessibilityTraits: return "modifier.accessibilityTraits"
        case .layoutPriority: return "modifier.layoutPriority"
        case .fixedSize: return "modifier.fixedSize"
        case .listRowSeparator: return "modifier.listRowSeparator"
        case .listRowBackground: return "modifier.listRowBackground"
        case .clipped: return "modifier.clipped"
        case .rotation: return "modifier.rotationEffect"
        case .scale: return "modifier.scaleEffect"
        case .brightness: return "modifier.brightness"
        case .clipShape: return "modifier.clipShape"
        case .hover: return "modifier.onHover"
        case .tap: return "modifier.onTapGesture"
        case .offset: return "modifier.offset"
        case .position: return "modifier.position"
        case .alignmentGuide: return "modifier.alignmentGuide"
        case .gridCell: return "modifier.gridColumnAlignment"
        case .spinner: return "modifier.rotationEffect"
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
        case .accessibilityValue: return "accessibilityValue"
        case .accessibilityHint: return "accessibilityHint"
        case .accessibilityHidden: return "accessibilityHidden"
        case .accessibilityElement: return "accessibilityElement"
        case .accessibilityTraits: return "accessibilityTraits"
        case .layoutPriority: return "layoutPriority"
        case .fixedSize: return "fixedSize"
        case .listRowSeparator: return "listRowSeparator"
        case .listRowBackground: return "listRowBackground"
        case .clipped: return "clipped"
        case .rotation: return "rotationEffect"
        case .scale: return "scaleEffect"
        case .brightness: return "brightness"
        case .clipShape: return "clipShape"
        case .hover: return "onHover"
        case .tap: return "onTapGesture"
        case .offset: return "offset"
        case .position: return "position"
        case .alignmentGuide: return "alignmentGuide"
        case .gridCell: return "gridColumnAlignment"
        case .spinner: return "spinner"
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
    /// SR1 round 6 block 37: a Slider; its children are the label and the minimum / maximum value labels that exist.
    case slider(SliderSpec)
    case image(ImageSpec)
    case color(ResolvedColor)
    /// Issue #60: a `LinearGradient` / `RadialGradient` view; the host rasterises it into a bitmap of the node's frame.
    case gradient(ResolvedGradient)
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
    /// A shape node's geometry as of the last change detection (R2: geometry is animated like the frame).
    var snapGeometry: ShapeGeometry?
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
    /// The frame layout computed before snapping to device pixels (#44): what SwiftUI scales under `.scaleEffect`.
    var exactFrame: LayoutRect = .zero
    /// The snapped frame in the coordinates of the nearest `.scaleEffect` ancestor (origin 0 at its frame), set by that ancestor's local placement (#44).
    var scaleLocalFrame: LayoutRect?
    /// Text memo: measured sizes for the current text, keyed by wrap width (nil = no wrap).
    var memoText: String?
    var memo: [CGFloat?: LayoutSize] = [:]
    /// The first and last line baselines of the memoised text measurements, keyed like `memo` (round 5 block 33, baseline alignment).
    var memoBase: [CGFloat?: (first: CGFloat, last: CGFloat)] = [:]
    /// R5: the shrunk font (`minimumScaleFactor`) that produced each measured size, by proposed width; absent when the text was not shrunk.
    var memoScaledFont: [CGFloat?: Font] = [:]
    /// The `minimumScaleFactor` the memo was measured with.
    var memoScaleFactor: CGFloat = 1
    /// Cache owned by a custom `Layout` container.
    var layoutStorage: Any?
    /// Retired-row state, used only when this node retains removed row state (List).
    var rowCache = RowStateCache()
    /// Scroll offset of a ScrollView node, in logical points, clamped by the layout pass.
    var scrollOffset: CGFloat = 0
    /// Slider nodes: the control (track and thumb) rectangle set by the layout pass, window points; the drag that is under way and where on the thumb it grabbed.
    var sliderTrack: LayoutRect = .zero
    var sliderDragging = false
    /// `.onHover` nodes: whether the pointer is inside (the last state the action was told).
    var hovered = false
    /// GeometryReader (R1): the size layout last gave this node, and the size its content was last built for.
    var geometrySize: LayoutSize?
    var geometryBuilt: LayoutSize?
    /// The proxy inputs the content was last built from (size, global origin, named-space origins): a move at the same size rebuilds it too (#57).
    var geometryBuiltProxy: GeometryInputs?
    /// The anchored frames the reader's content read through `proxy[anchor]` (issue #68): the reader is rebuilt when one of them moves.
    var geometryAnchorReads: AnchorReadLog?
    /// The frame holder an `anchorPreference` modifier on this node hands out in its `Anchor`s; layout keeps it current.
    var anchorBox: AnchorFrameBox?
    var sliderGrab: CGFloat = 0
    /// Configured horizontal/vertical offsets; nil for legacy scroll nodes.
    var scrollOffsetX: CGFloat?
    var scrollOffsetY: CGFloat?
    /// Scroll state of a List or vertical ScrollView, set by the layout pass (#31). Nil for other nodes.
    var scrollState: ScrollState?
    /// A scroll bar drag under way: the pointer's y and the offset when the drag began (#31).
    var scrollDrag: (startY: CGFloat, startOffset: CGFloat)?
    /// A List's row extents in document coordinates (0 at the List's top edge, unscrolled), keyed by row instance; set by the layout pass (#31).
    var listRowExtents: [Int: (top: CGFloat, height: CGFloat)] = [:]
    /// Target opacity (own `.opacity` times the parent's target).
    var targetOpacity: Double = 1
    /// Presented (animated) values: what the last commit showed.
    var presentedFrame: LayoutRect = .zero
    var presentedOpacity: Double = 1
    /// A shape node's presented (animated) geometry; nil for other nodes. The commit record draws this, not the evaluated geometry.
    var presentedGeometry: ShapeGeometry?
    /// A `.scaleEffect` node's presented (animated) factors; nil for other nodes.
    var presentedScale: CGSize?
    var snapScale: CGSize?
    /// #54: the node's presented (animated) paint, and as of the last change detection. See `PaintInterpolation.swift`.
    var presentedPaint: PaintValues?
    var snapPaint: PaintValues?
    /// The node's evaluated paint (its animation target): a shape's explicit colour and stroke width, a `Color` view's colour, else the foreground style.
    var targetPaint: PaintValues? {
        var paint = basePaint
        if let roll = numericRoll {
            if paint == nil { paint = PaintValues(color: nil, lineWidth: nil) }
            paint?.roll = Double(roll.serial)
        }
        return paint
    }
    /// A Text's numeric-text roll state (`NumericTextRoll.swift`); nil unless `.contentTransition(.numericText…)` is in effect.
    var numericRoll: NumericRollState?
    private var basePaint: PaintValues? {
        switch kind {
        case .shape(let resolved):
            if let p = resolved.paint {
                return PaintValues(color: p.color.resolvingTint(environment), lineWidth: p.kind == .stroke ? p.lineWidth.map { Double($0) } : nil)
            }
            return style.foreground.map { PaintValues(color: $0, lineWidth: nil) }
        case .color(let resolved):
            return PaintValues(color: resolved, lineWidth: nil)
        default:
            return style.foreground.map { PaintValues(color: $0, lineWidth: nil) }
        }
    }
    /// A `.scaleEffect` node's evaluated factors (its animation target).
    var targetScale: CGSize? {
        if case .modifier(.scale(let x, let y, _)) = kind { return CGSize(width: x, height: y) }
        return nil
    }
    /// A shape node's evaluated geometry (its animation target).
    var targetGeometry: ShapeGeometry? {
        if case .shape(let resolved) = kind { return resolved.geometry }
        if case .modifier(.clipShape(let geometry, _)) = kind { return geometry }
        return nil
    }
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
        memoBase = [:]
        memoText = nil
        memoFont = nil
        selection = nil
        selectionAnchor = nil
        selectionCursor = nil
        menuEntries = nil
        presented = nil
        scrollOffsetX = nil
        scrollOffsetY = nil
        scrollState = nil
        scrollDrag = nil
        listRowExtents = [:]
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
    /// Modifier nodes of `.listRowSeparator` / `.listRowBackground` only: what the modifier asks of its List row (the host reads it from the row's subtree).
    public var rowStyle: ListRowStyle? = nil
    /// Slider nodes only (round 6 block 37): the value, bounds, step, track rectangle and thumb position.
    public var slider: ResolvedSlider? = nil
    /// List and vertical ScrollView nodes only (#31): the offset, content and viewport heights and whether a scroller shows. Nil for other nodes.
    /// A `var` with a nil default, like `slider` and `rowStyle`, so the memberwise initializer stays source compatible.
    public var scroll: ScrollState? = nil
    /// Modifier nodes of `.rotationEffect` only (F-path, #35): the angle and anchor. The node's frame is the child's frame (layout is unchanged); the host applies the rotation.
    public var rotation: ResolvedRotation? = nil
    /// Modifier nodes of `.scaleEffect` only (SR2 R4, #39): the presented (animated) factors and the anchor. Layout is unchanged; the host scales the subtree.
    public var scaleEffect: ResolvedScale? = nil
    /// Modifier nodes of `.brightness` only (SR2 R4, #39): the amount added to each sRGB channel of the subtree's colours.
    public var brightness: Double? = nil
    /// Modifier nodes of `.clipShape` only (SR2 R6, #41): the presented clip geometry (in this node's frame) and its fill rule.
    public var clipShape: ResolvedClipShape? = nil
    /// The frame before device-pixel snapping (#44), when it differs from `frame` and the node is not moving; nil otherwise. A host scales this under
    /// `.scaleEffect`: SwiftUI scales the laid-out geometry, not its snapped pixels.
    public var exactFrame: LayoutRect? = nil
    /// The snapped frame in the coordinates of the nearest `.scaleEffect` ancestor (#44); nil outside one. A host draws a scaled subtree from these.
    public var scaleLocalFrame: LayoutRect? = nil
    /// Text nodes made of styled runs only (#68): the runs with fonts and colours resolved, and the line limit. Nil for a plain Text (the node is then the string in `text`
    /// with `style`) and for every other node.
    public var styledText: ResolvedStyledText? = nil
    /// Button, Toggle and Slider nodes only (#54): the environment's `.tint(_:)`, nil when none is set (the accent colour then applies). A host paints the control's accent in it.
    public var tint: ResolvedColor? = nil
    /// Gradient nodes only (#60): the stops and geometry the host rasterises into a bitmap of the node's frame.
    public var gradient: ResolvedGradient? = nil
    /// Text nodes under `.contentTransition(.numericText…)` only, while an animated text change is rolling (#55): each glyph of the old and new text with its offset
    /// and opacity. The host paints these instead of `text`. Nil otherwise (the node is then plain text).
    public var numericRoll: ResolvedNumericRoll? = nil
}

/// What `.clipShape(_:style:)` asks of its subtree: paint only inside `geometry` laid out in the modifier node's frame.
public struct ResolvedClipShape: Equatable, Sendable {
    public let geometry: ShapeGeometry
    public let fillStyle: FillStyle
    public init(geometry: ShapeGeometry, fillStyle: FillStyle) { self.geometry = geometry; self.fillStyle = fillStyle }
}

/// What `.scaleEffect(x:y:anchor:)` asks of its subtree: painting scaled by (`x`, `y`) about `anchor` (a unit point of the modifier node's frame).
public struct ResolvedScale: Equatable, Sendable {
    public let x: CGFloat
    public let y: CGFloat
    public let anchor: UnitPoint
    public init(x: CGFloat, y: CGFloat, anchor: UnitPoint) { self.x = x; self.y = y; self.anchor = anchor }
}

/// What `.rotationEffect(_:anchor:)` asks of its subtree: a rotation by `angle` about `anchor` (a unit point of the modifier node's frame). Positive angles turn clockwise on screen (y down), as in SwiftUI.
public struct ResolvedRotation: Equatable, Sendable {
    public let angle: Angle
    public let anchor: UnitPoint
    public init(angle: Angle, anchor: UnitPoint) { self.angle = angle; self.anchor = anchor }
}

/// What `.listRowSeparator(_:)` and `.listRowBackground(_:)` ask of a List row.
public struct ListRowStyle: Equatable, Sendable {
    /// `.listRowSeparator(.hidden)`; nil when this modifier does not set the separator.
    public var separatorHidden: Bool?
    /// `.listRowBackground(_:)`: true when the modifier set a background (also when it is nil, which removes it).
    public var setsBackground: Bool
    /// The resolved fill when the background is a Color or a rectangle filled with a Color; nil for `listRowBackground(nil)`.
    public var background: ResolvedColor?
    /// The background is some other view (not a Color or a filled Rectangle): the host does not draw it and says so.
    public var backgroundUnsupported: Bool
    public init(separatorHidden: Bool? = nil, setsBackground: Bool = false, background: ResolvedColor? = nil, backgroundUnsupported: Bool = false) {
        self.separatorHidden = separatorHidden; self.setsBackground = setsBackground; self.background = background; self.backgroundUnsupported = backgroundUnsupported
    }
}

/// The argument of `.listRowBackground`, resolved when the modifier is built.
struct ListRowBackground {
    let style: ListRowStyle
}

extension ResolvedNode {
    /// The same node with a new frame, opacity and children (a removal transition presents a frozen subtree moved and faded).
    func replacing(frame: LayoutRect, pixelFrame: PixelRect, opacity: Double, children: [ResolvedNode]) -> ResolvedNode {
        ResolvedNode(id: id, instance: instance, kind: kind, text: text, frame: frame, pixelFrame: pixelFrame, opacity: opacity,
                     selection: selection, marked: marked, children: children, labelsHidden: labelsHidden, toggleStyle: toggleStyle,
                     fieldStyle: fieldStyle, placeholder: placeholder, accessibility: accessibility, style: style, image: image,
                     imageSizing: imageSizing, color: color, shapeStorage: shapeStorage, menu: menu, presentation: presentation, shortcut: shortcut,
                     buttonStyle: buttonStyle, isDefaultButton: isDefaultButton, listStyle: listStyle, rowStyle: rowStyle, slider: slider, scroll: scroll, rotation: rotation,
                     styledText: styledText)
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
    /// Accessibility modifier nodes only (round 5 block 32): the parameters the modifier carries; the host applies them to the element beneath.
    public var hint: String? = nil
    public var isHidden: Bool = false
    /// "ignore", "combine" or "contain" on an `.accessibilityElement(children:)` node.
    public var childBehavior: String? = nil
    /// `accessibilityAddTraits` names (`isButton`, `isHeader`, `isSelected`, `isImage`, `isStaticText`, `isLink`, `updatesFrequently`, ...) and `accessibilityRemoveTraits`.
    public var addedTraits: [String] = []
    public var removedTraits: [String] = []
    /// False under `.allowsHitTesting(false)` (R1, #36): the node and its subtree take no pointer hits. Accessibility actions are unaffected, as in SwiftUI.
    public var allowsHitTesting: Bool = true
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
    /// onChange actions of the current evaluation, run after the update commits (SwiftUI): what they write is the next update pass.
    var pendingChanges: [() -> Void] = []
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
    /// Set when the tree has contained an `.alignmentGuide` or a custom alignment: stacks then check their children for explicit guides (issue #68). Never reset.
    var alignmentGuidesLive = false
    /// Live `.onPreferenceChange` nodes; legacy flushes skip observer traversal entirely.
    private var preferenceObserverNodes: Set<NodeID> = []
    /// Observation change callbacks received (tests check that retired registrations stay silent).
    private(set) var observationCallbacks = 0
    private var dirty: [NodeID: Node] = [:]
    /// Live GeometryReader nodes (R1): their content is built from the size layout gives them, so a layout that changes it re-evaluates them.
    var geometryNodes: [NodeID: Node] = [:]
    /// True while the dirty nodes are being evaluated: a transaction boundary inside an evaluation is not a new transaction.
    private var evaluating = false
    /// A transaction-boundary settle evaluated changes outside a flush: they still need their commit (and the onChange actions they queued their
    /// run), though no node is dirty any more. `scheduleFlush` honours it; `flush` clears it.
    private var settledAwaitingFlush = false
    /// Transactions queued on this graph (by `withAnimation` bodies that wrote its state, and its own `.animation(_:value:)` changes); a commit takes them.
    private var queued: [AnimationTransaction] = []
    /// True while the onChange actions of a flush run: a transaction they open commits the triggering pass first (see `noteWrite`).
    private var runningChangeActions = false
    /// The state evaluated since the last commit has not been committed yet (the triggering pass of the running onChange actions).
    private var uncommitted = false
    private var flushScheduled = false
    private(set) var sequence = 0
    private var instanceCounter = 0
    /// Host-supplied time in seconds of the last `tick(now:)`; nil before the first tick. It has no required origin. A motion
    /// does not start at it: a motion begins at the next tick (see `advanceMotions`).
    var clock: Double?
    /// Steps of the spinner nodes as of the last tick (#60).
    private var shownSpinnerSteps: [String: Int] = [:]
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
    /// Size of a NON-resizable `Image(systemName:)` drawn at the environment font (nil font = the default body font): SwiftUI sizes the
    /// symbol by the font, not by the proposal. Nil (the default) keeps the natural size above.
    public var imageFontIntrinsicSize: (ImageReference, Font?) -> LayoutSize? = { _, _ in nil } {
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
        TransactionContext.register(self)
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
        c.queuedTransactions = queued.count + TransactionContext.unattachedTransactions.count
        c.deferredCompletions = TransactionContext.deferred.count
        return c
    }

    /// Applies pending invalidations (coalesced), lays out, and always emits one commit record.
    public func flush() {
        let flushStart = profile == nil ? 0 : GraphProfile.now()
        var rounds = 0
        var presentedBeforeAppear = false
        settledAwaitingFlush = false
        while rounds < 64 {
            drainDirty(&rounds)
            if !preferenceObserverNodes.isEmpty { deliverPreferenceChanges() }
            applyWindowSchemeRequest()
            if dirty.isEmpty, !pendingChanges.isEmpty {
                // The update has been evaluated: run the onChange actions it queued. Their writes are the next pass. No commit here: the
                // transactions queued so far stay queued, so the next pass (and the commit that ends the flush) carries the transaction that
                // triggered the action (SwiftUI: a write inside onChange during an animated transaction inherits it).
                let actions = pendingChanges
                pendingChanges = []
                runningChangeActions = true
                uncommitted = true
                for action in actions { action() }
                runningChangeActions = false
                uncommitted = false
                continue
            }
            if dirty.isEmpty {
                if pendingAppear.isEmpty {
                    // A GeometryReader builds its content from the size layout gives it: lay out, and evaluate the readers whose size changed.
                    if !geometryNodes.isEmpty, markStaleGeometry() { continue }
                    break
                }
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
        settledAwaitingFlush = false
        if !presentedBeforeAppear { commit() }
    }

    /// What a GeometryReader's proxy is built from: its size, its origin in graph coordinates, and the origin of the nearest enclosing view for each
    /// `.coordinateSpace(name:)` (the node where the environment's name list grows; the modifier is layout-transparent, so its frame is the named view's).
    func geometryInputs(_ node: Node, size: LayoutSize) -> GeometryInputs {
        var named: [AnyHashable: CGPoint] = [:]
        var current: Node? = node
        while let a = current {
            let names = a.environment.coordinateSpaceNames
            let inherited = a.parent?.environment.coordinateSpaceNames.count ?? 0
            if names.count > inherited {
                for name in names[inherited...] where named[name] == nil {
                    named[name] = CGPoint(x: a.frame.minX, y: a.frame.minY)
                }
            }
            current = a.parent
        }
        return GeometryInputs(size: size, origin: CGPoint(x: node.frame.minX, y: node.frame.minY), named: named)
    }

    /// Lays the tree out and marks dirty every live GeometryReader whose laid-out size, origin or named-space origins differ from what its content was
    /// built for. True when any was marked.
    func markStaleGeometry() -> Bool {
        layoutRoot()
        var marked = false
        for (id, node) in geometryNodes {
            guard node.alive, nodes[id] === node else { geometryNodes[id] = nil; continue }
            guard let size = node.geometrySize else { continue }
            if size == node.geometryBuilt, geometryInputs(node, size: size) == node.geometryBuiltProxy,
               !(node.geometryAnchorReads?.isStale ?? false) { continue }
            node.fullDirty = true
            dirty[id] = node
            marked = true
        }
        if marked { layoutEpoch += 1 }
        return marked
    }

    /// Evaluates the dirty nodes in rounds until none is left (or the round bound is hit): the coalesced evaluation `flush` runs.
    private func drainDirty(_ rounds: inout Int) {
        while !dirty.isEmpty, rounds < 64 {
            rounds += 1
            evaluationRound += 1
            // Shallow nodes first so a dirty ancestor evaluates its dirty descendants; ties in creation order (deterministic and
            // an integer compare, where comparing path strings would cost more than evaluating a small node).
            let batch = dirty.values.sorted {
                $0.depth != $1.depth ? $0.depth < $1.depth : $0.instance < $1.instance
            }
            dirty.removeAll()
            evaluating = true
            for node in batch where node.alive && nodes[node.id] === node {
                // Evaluating a node re-evaluates everything below it, so a dirty node already reached from a dirty ancestor
                // in this round is done.
                if node.evaluatedRound == evaluationRound { continue }
                // A node marked only because a ForEach data source it expands changed, and whose own view has not been
                // replaced, expands the same ForEach again: its unchanged rows need no evaluation (see `expand`).
                evaluate(node, refresh: node.dataStale && !node.fullDirty && !node.viewReplaced)
            }
            evaluating = false
        }
    }

    /// A transaction boundary (`withAnimation`, `withTransaction`, before their body runs): the changes made so far are a transaction of their own, so the
    /// dirty nodes they dirtied are evaluated now, before the new transaction's changes are made. Nothing is committed here; the next flush commits.
    /// Mac (SwiftUI): `onAppear { value = 1; value = 2; withAnimation { value = 3; value = 4 } }` evaluates the body with 0, 2, 4, 4, never 1.
    func settleAtTransactionBoundary() {
        guard !evaluating, !closed, !dirty.isEmpty else { return }
        var rounds = 0
        drainDirty(&rounds)
        // The settle evaluated outside a flush. A caller that is not in one (a Task, a timer) leaves no dirty node for the scheduled flush to find, so
        // the settled state and any onChange actions it queued would wait for an unrelated flush: ask for one.
        settledAwaitingFlush = true
        scheduleFlush()
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

    // MARK: Scrolling (#31)

    /// The vertical offset of a scroll container (a List, a vertical ScrollView or the legacy scroll node), or nil for other nodes.
    private func verticalOffset(_ target: Node) -> CGFloat? {
        switch target.kind {
        case .scroll: return target.scrollOffset
        case .scrollView(let configuration): return configuration.axes.contains(.vertical) ? (target.scrollOffsetY ?? 0) : nil
        case .stack(let spec) where spec.name == "List": return target.scrollOffsetY ?? 0
        default: return nil
        }
    }

    /// Stores a vertical offset (already clamped) and keeps the node's scroll state in step with it.
    private func setVerticalOffset(_ target: Node, _ value: CGFloat) {
        if case .scroll = target.kind { target.scrollOffset = value } else { target.scrollOffsetY = value }
        if let state = target.scrollState {
            target.scrollState = ScrollState(offsetY: Double(value), contentHeight: state.contentHeight, viewportHeight: state.viewportHeight,
                                             showsScroller: state.showsScroller)
        }
    }

    /// Moves a scroll container to `proposed`, clamped to 0...maxOffset. Returns whether the offset changed.
    @discardableResult
    private func moveScroll(_ target: Node, to proposed: CGFloat) -> Bool {
        guard let state = target.scrollState, let current = verticalOffset(target) else { return false }
        let clamped = min(max(0, proposed), CGFloat(state.maxOffset))
        guard clamped != current else { return false }
        setVerticalOffset(target, clamped)
        return true
    }

    /// The page distance: the viewport less the page overlap, never negative.
    private func pageDistance(_ target: Node) -> CGFloat? {
        guard let state = target.scrollState else { return nil }
        return max(0, CGFloat(state.viewportHeight) - ScrollerMetrics.pageOverlap)
    }

    /// The innermost scroll container (the deepest node with a scroll state) whose frame contains the point, in root points.
    private func innermostScrollContainer(atX x: CGFloat, y: CGFloat) -> Node? {
        var found: Node?
        var foundDepth = -1
        func visit(_ target: Node, depth: Int) {
            let frame = target.frame
            if target.scrollState != nil, x >= frame.minX, x < frame.maxX, y >= frame.minY, y < frame.maxY, depth >= foundDepth {
                found = target
                foundDepth = depth
            }
            for child in target.childNodes { visit(child, depth: depth + 1) }
        }
        if let root { visit(root, depth: 0) }
        return found
    }

    /// Scrolls the innermost scroll container under a point (root space, logical points) by `lines` wheel lines. A positive `lines` moves the
    /// content down (reveals content below, the offset grows); the host converts the wheel's delta (`ScrollerMetrics.pointsPerLine` per line).
    /// Returns whether the offset changed; the change shows at the next flush.
    @discardableResult
    public func scrollWheel(atX x: Double, y: Double, lines: Double) -> Bool {
        guard let target = innermostScrollContainer(atX: CGFloat(x), y: CGFloat(y)), let current = verticalOffset(target) else { return false }
        // A List scrolls one row per wheel line (NSTableView's line scroll is the row height; measured M2, #31); a ScrollView 10 pt.
        let line = target.listRowExtents.values.map(\.height).min() ?? ScrollerMetrics.pointsPerLine   // only a List records row extents
        return moveScroll(target, to: current + CGFloat(lines) * line)
    }

    /// The id of the innermost scroll container under a point (root space, logical points), nil when none. A host pages it with a key when no
    /// List holds the keyboard (`HostScrollInput.key`, issue #31).
    public func scrollContainerID(atX x: Double, y: Double) -> String? {
        innermostScrollContainer(atX: CGFloat(x), y: CGFloat(y))?.idString
    }

    /// Pages a scroll container down or up by a page (the viewport less `ScrollerMetrics.pageOverlap`). Returns whether the offset changed.
    @discardableResult
    public func scrollPage(_ id: String, down: Bool) -> Bool {
        guard let target = node(id), let page = pageDistance(target), let current = verticalOffset(target) else { return false }
        return moveScroll(target, to: current + (down ? page : -page))
    }

    /// Moves a scroll container to its end (`end: true`) or its start. Returns whether the offset changed.
    @discardableResult
    public func scrollToEdge(_ id: String, end: Bool) -> Bool {
        guard let target = node(id), let state = target.scrollState else { return false }
        return moveScroll(target, to: end ? CGFloat(state.maxOffset) : 0)
    }

    /// Geometry of a scroll bar in root points: the track's top, the thumb's top and length, and the offset with its maximum.
    private struct ScrollBarGeometry {
        let offset: CGFloat
        let maxOffset: CGFloat
        let track: CGFloat
        let thumb: CGFloat
        let thumbTop: CGFloat
    }

    private func scrollBarGeometry(_ target: Node) -> ScrollBarGeometry? {
        guard let state = target.scrollState, let offset = verticalOffset(target) else { return nil }
        let viewport = CGFloat(state.viewportHeight)
        let track = ScrollerMetrics.trackLength(viewport: viewport)
        let thumb = ScrollerMetrics.thumbLength(viewport: viewport, content: CGFloat(state.contentHeight))
        let fraction = state.maxOffset > 0 ? offset / CGFloat(state.maxOffset) : 0
        let thumbTop = target.frame.minY + ScrollerMetrics.thumbInsetTop + fraction * max(0, track - thumb)
        return ScrollBarGeometry(offset: offset, maxOffset: CGFloat(state.maxOffset), track: track, thumb: thumb, thumbTop: thumbTop)
    }

    /// A press on a scroll bar at root `y`. In the thumb it starts a drag (`scrollBarDrag` maps the pointer to the offset). In the track it pages
    /// toward the press once.
    public func scrollBarPress(_ id: String, atY y: Double) {
        guard let target = node(id), let geometry = scrollBarGeometry(target), let page = pageDistance(target) else { return }
        let pointer = CGFloat(y)
        if pointer >= geometry.thumbTop, pointer <= geometry.thumbTop + geometry.thumb {
            target.scrollDrag = (startY: pointer, startOffset: geometry.offset)
        } else {
            target.scrollDrag = nil
            moveScroll(target, to: geometry.offset + (pointer < geometry.thumbTop ? -page : page))
        }
    }

    /// Drags the thumb begun by `scrollBarPress`: the offset moves by `dy * maxOffset / (track - thumb)`, clamped. Ignored without a drag.
    public func scrollBarDrag(_ id: String, toY y: Double) {
        guard let target = node(id), let drag = target.scrollDrag, let geometry = scrollBarGeometry(target) else { return }
        let travel = geometry.track - geometry.thumb
        guard travel > 0 else { return }
        let delta = (CGFloat(y) - drag.startY) * geometry.maxOffset / travel
        moveScroll(target, to: drag.startOffset + delta)
    }

    /// Ends the thumb drag, if one is under way.
    public func scrollBarRelease(_ id: String) {
        node(id)?.scrollDrag = nil
    }

    /// Moves a List's offset by the smallest amount that brings the row tagged `tag` fully into the viewport (no move when it is already visible).
    /// Returns whether the offset changed. The row's extents come from the last layout.
    @discardableResult
    public func scrollListRow(_ listID: String, tag: AnyHashable) -> Bool {
        guard let list = node(listID), let state = list.scrollState, let current = verticalOffset(list),
              let row = taggedRows(of: list).first(where: { $0.tag == tag })?.node,
              let extent = list.listRowExtents[row.instance] else { return false }
        let top = extent.top
        let bottom = extent.top + extent.height
        let viewport = CGFloat(state.viewportHeight)
        let target: CGFloat
        if top < current { target = top } else if bottom > current + viewport { target = bottom - viewport } else { return false }
        return moveScroll(list, to: target)
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
        // Issue #60: an indeterminate ProgressView spins by the host clock. Nothing is re-evaluated; the resolved rotation of a spinner node follows `clock`, so a commit is
        // emitted only when some spinner's step changed since the last one.
        let spinnerMoved = ModifierSpec.spinnersCreated && spinnersChangedStep()
        if wasAnimating || spinnerMoved { emit(animationNames: []) }
        TransactionContext.drainDeferred()
    }

    /// The step (0, 1, 2, ... without bound) of a spinner on the host clock: one step per `period / steps` seconds; 0 before the first tick.
    func spinnerStep(steps: Int, period: Double) -> Int {
        guard let clock, steps > 0, period > 0, clock.isFinite else { return 0 }
        return Int((clock / period * Double(steps)).rounded(.down))
    }

    /// The spinner steps shown by the last commit, by node id; true when any live spinner is now at another step (or a new one appeared).
    private func spinnersChangedStep() -> Bool {
        var current: [String: Int] = [:]
        for node in nodes.values where node.alive {
            if case .modifier(.spinner(let steps, let period)) = node.kind { current[node.idString] = spinnerStep(steps: steps, period: period) }
        }
        defer { shownSpinnerSteps = current }
        return current != shownSpinnerSteps
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
        for queued in takeQueued() { queued.settleIfDone() }
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
            // A modifier over an erased empty view (AnyView(EmptyView()).frame(...)) is not a stack child: it takes no space and no stack spacing
            // (measured on macOS 27 in block 41 any-view: the following rows sit where they would without it).
            if let primitive = view as? PrimitiveView, case .modifier = primitive.nodeKind, let content = primitive.nodeContent, isErasedEmpty(content) {
                return
            }
            // A modifier chain over a `Group` applies to each member of the group (SwiftUI: a Group is transparent, so a modifier on it modifies every child).
            if let chain = groupModifierChain(view, info) {
                var members: [Entry] = []
                expand(chain.group, prefix: [], into: &members, refreshable: &refreshable)
                for member in members {
                    var wrapped: any View = member.view
                    for spec in chain.specs.reversed() { wrapped = ModifierWrapper(inner: wrapped, spec: spec) }
                    let wrappedInfo = ViewTypes.info(for: wrapped)
                    out.append(Entry(relative: prefix + Array(member.relative.dropLast()) + [Segment.type(wrappedInfo.name)], view: wrapped, info: wrappedInfo))
                }
                refreshable = false
                return
            }
            // `Group { A; B }.background(X)` (or over a modifier chain on a Group) is `A.background(X)` and `B.background(X)`.
            if hasGroupBase(view), let wrapper = view as? GroupBaseDistributable {
                let base = wrapper.groupBase
                do {
                    var members: [Entry] = []
                    expand(base, prefix: [], into: &members, refreshable: &refreshable)
                    for member in members {
                        let wrapped = wrapper.rewrapped(over: member.view)
                        let wrappedInfo = ViewTypes.info(for: wrapped)
                        out.append(Entry(relative: prefix + Array(member.relative.dropLast()) + [Segment.type(wrappedInfo.name)], view: wrapped, info: wrappedInfo))
                    }
                    refreshable = false
                    return
                }
            }
            out.append(Entry(relative: prefix + [.type(info.name)], view: view, info: info))
        }
    }

    /// A wrapper (`background`) over a Group, or over a modifier chain on a Group: distributed over the members by `expand`.
    func hasGroupBase(_ view: any View) -> Bool {
        guard let wrapper = view as? GroupBaseDistributable else { return false }
        let base = wrapper.groupBase
        return base is any GroupView || groupModifierChain(base, ViewTypes.info(for: base)) != nil
    }

    /// The modifiers (outermost first) of a chain of modifier views that ends in a `Group`, with the group; nil for any other view.
    func groupModifierChain(_ view: any View, _ info: ViewTypes.Info) -> (specs: [ModifierSpec], group: any View)? {
        guard let read = info.readPrimitive else { return nil }
        var specs: [ModifierSpec] = []
        var current = read(view)
        while case .modifier(let spec) = current.kind, let content = current.content {
            specs.append(spec)
            if content is any GroupView { return (specs, content) }
            guard let next = ViewTypes.info(for: content).readPrimitive else { return nil }
            current = next(content)
        }
        return nil
    }

    /// `AnyView` (any depth) around `EmptyView`: a view with no content. Only a modifier directly around it is dropped (`expand`). Stacked modifiers
    /// (`AnyView(EmptyView()).padding().frame(...)`) are left as they were: only the single frame over it was measured on macOS 27 (block 41
    /// any-view), and what SwiftUI lays out for padding or a background over an empty view was not, so extending the rule would be a guess.
    private func isErasedEmpty(_ view: any View) -> Bool {
        if view is EmptyView { return true }
        if let erased = view as? AnyView { return isErasedEmpty(erased.wrapped) }
        return false
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
        if !geometryNodes.isEmpty { geometryNodes[id] = nil }
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
            if !pendingAppear.isEmpty { pendingAppear.append { action(old, new) }; return }
            if evaluating { pendingChanges.append { action(old, new) }; return }
            action(old, new)
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
            if let applyAt = contribution.applyAt { applyAt(node, &values) } else { contribution.apply(&values) }
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
        if !alignmentGuidesLive { noteAlignmentGuides(kind) }
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
            node.style = ResolvedStyle(font: node.environment.textFont, foreground: node.environment.foregroundStyle?.resolvingTint(node.environment), colorScheme: node.environment.colorScheme)
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
                enqueue(AnimationTransaction(animation: animation, completion: nil, scope: node))
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
        } else if case .stack(let labelSpec) = kind, labelSpec.name == "Label", let styled = styledLabelContent(node) {
            produced = styled
        } else {
            produced = node.primitiveContent
        }

        guard let produced else {
            reconcile(node, entries: [])
            reducePreferencesUpward(from: node)
            return
        }
        let producedInfo = ViewTypes.info(for: produced)
        if producedInfo.shape == .leaf, groupModifierChain(produced, producedInfo) == nil, !hasGroupBase(produced) {
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
        case .text(let raw):
            let string = node.environment.textCase?.apply(raw) ?? raw
            var font = node.environment.textFont
            let factor = node.environment.minimumScaleFactor
            if factor < 1 {
                let base = font ?? .body
                let id = "\(base.id)|minimumScaleFactor(\(factor))"
                font = base.metadata.map { Font(id: id, metadata: $0) } ?? Font(id: id)
            }
            let lineLimit = node.environment.lineLimit
            if let signature = styledLayoutSignature(of: node) {
                key = .styledText(string + signature, font, lineLimit)   // runs with their own fonts and attributes (#68)
            } else {
                key = font?.metadata == nil && lineLimit == nil
                    ? .text(string, font?.id)
                    : .styledText(string, font, lineLimit)
            }
        case .textField, .textEditor:
            let font = node.environment.textFont
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
        case .modifier(.alignmentGuide): key = .always
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
        case .user, .textField, .textEditor, .toggle, .slider, .menu: return true
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
        case .slider(let spec): _ = spec.read()
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
        if case .user = kind {
            if node.info.isGeometryReader, let reader = node.view as? any GeometryReading {
                geometryNodes[node.id] = node
                // Until layout has given the reader a size it has no content (so nothing appears with a zero size); the layout pass then evaluates it again.
                guard let size = node.geometrySize else { node.geometryBuilt = nil; node.geometryBuiltProxy = nil; return EmptyView() }
                node.geometryBuilt = size
                let inputs = geometryInputs(node, size: size)
                node.geometryBuiltProxy = inputs
                let reads = AnchorReadLog()
                node.geometryAnchorReads = reads
                return reader.makeContent(GeometryProxy(size: CGSize(width: size.width, height: size.height),
                                                        globalOrigin: inputs.origin, namedOrigins: inputs.named, reads: reads))
            }
            return node.view.evaluateBody()
        }
        return node.primitiveContent
    }

    // MARK: Invalidation

    /// Queues `transaction` for this graph's next commit. A closed graph never commits again, so it takes none (false).
    @discardableResult
    func enqueue(_ transaction: AnimationTransaction) -> Bool {
        guard !closed else { return false }
        queued.append(transaction)
        return true
    }

    /// Whether `transaction` waits in this graph's queue for its next commit.
    func isQueued(_ transaction: AnimationTransaction) -> Bool { queued.contains { $0 === transaction } }

    /// Whether any transaction waits in this graph's queue for its next commit.
    var hasQueuedTransactions: Bool { !closed && !queued.isEmpty }

    /// The transactions pending for the next commit of this graph (a removal reads them to decide whether it animates).
    var pendingTransactions: [AnimationTransaction] { queued + TransactionContext.unattachedTransactions }

    private func takeQueued() -> [AnimationTransaction] {
        let out = TransactionContext.takeUnattached() + queued
        queued = []
        return out
    }

    /// A write to this graph's state. Inside a `withAnimation` body it records the graph in the frame (the transaction will be queued here). Made by an
    /// onChange action, it is state the action's own pass has not committed.
    private func noteWrite() {
        TransactionContext.touch(self)
        if runningChangeActions { uncommitted = true }
    }

    /// A transaction begins (`TransactionContext.begin`, after the settle) while this graph runs its onChange actions: the pass that triggered them is
    /// committed first, under the transaction it was made in. SwiftUI keeps each change's own transaction, so the trigger must not take the action's
    /// animation, nor lose its own to `withAnimation(nil)`. An onChange write made with no transaction of its own begins nothing, so it inherits the
    /// trigger's transaction and commits nothing extra.
    func commitTriggerBeforeTransaction() {
        guard runningChangeActions, uncommitted, !evaluating, !closed else { return }
        commit()
        uncommitted = false
    }

    func noteChange(_ node: Node) {
        guard node.alive, nodes[node.id] === node else { return }
        noteWrite()
        node.fullDirty = true
        dirty[node.id] = node
        scheduleFlush()
    }

    /// A ForEach data source that `node` expands changed. The node is re-expanded at the next flush.
    func noteDataChange(_ node: Node) {
        guard node.alive, nodes[node.id] === node else { return }
        noteWrite()
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
            if !self.dirty.isEmpty || self.settledAwaitingFlush || !self.pendingChanges.isEmpty || !self.queued.isEmpty { self.flush() }
        }
    }

    // MARK: Commit

    /// Commits the pass made so far under `transaction` (a nested `withAnimation` boundary or end; see `TransactionContext.begin`), taking along what
    /// is already queued (an `.animation(_:value:)` change the pass made). Where this graph is evaluating, the transaction is queued as before.
    func commitSegment(_ transaction: AnimationTransaction) {
        guard !closed else { return }
        if evaluating { enqueue(transaction); return }
        var rounds = 0
        drainDirty(&rounds)
        commit(extra: transaction)
        uncommitted = false
    }

    private func commit(extra: AnimationTransaction? = nil) {
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
        // Readers whose size changed in this layout (a commit outside a flush, such as a transaction boundary) are settled here: bounded, since a reader's size
        // never depends on its own content.
        var geometryPasses = 0
        while !geometryNodes.isEmpty, geometryPasses < 4, markStaleGeometry() {
            geometryPasses += 1
            var rounds = 0
            drainDirty(&rounds)
            layoutRoot()
        }
        assignOpacity(root, parent: 1)
        layoutEpoch += 1
        if profiling { lap(&profile!.layoutNS) }
        var changed: [Node] = []
        collectChanged(root, into: &changed)
        let transactions = takeQueued() + (extra.map { [$0] } ?? [])
        // Motions end in path order (completion order must not depend on how the tree was walked), so sort when a motion
        // can start or end in this commit.
        if !transactions.isEmpty || changed.contains(where: { $0.motion != nil }) {
            changed.sort { $0.idString < $1.idString }
        }
        if profiling { lap(&profile!.diffNS) }
        applyTransactions(transactions, changed: changed)
        if profiling { lap(&profile!.transactionNS) }
        emit(animationNames: transactions.filter { !$0.settlesOnly }.compactMap { $0.animation?.name })   // a settles-only block animated nothing: it names no animation
        TransactionContext.drainDeferred()
    }

    /// Collects the nodes whose layout target (frame or target opacity) differs from the previous commit's, and records the
    /// new targets as the baseline for the next.
    private func collectChanged(_ node: Node, into out: inout [Node]) {
        updateNumericRoll(node)
        let geometry = node.targetGeometry
        let scale = node.targetScale
        let paint = node.targetPaint
        if node.frame != node.snapFrame || node.targetOpacity != node.snapOpacity || geometry != node.snapGeometry || scale != node.snapScale || paint != node.snapPaint {
            out.append(node)
            node.snapFrame = node.frame
            node.snapOpacity = node.targetOpacity
            node.snapGeometry = geometry
            node.snapScale = scale
            node.snapPaint = paint
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
            text = node.environment.textCase?.apply(string) ?? string
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
            if spec.sizing.isResizable || spec.sizing.scalesToFit || spec.sizing.isNonDefault {
                imageSizing = spec.sizing
            }
        }
        var color: ResolvedColor?
        if case .color(let resolved) = kind { color = node.presentedPaint?.color ?? resolved }
        var shape: ResolvedShape?
        if case .shape(let resolvedShape) = kind {
            var paint = resolvedShape.paint
            if let p = paint, case .semantic(let name) = p.color, name == "tint" { paint = p.withColor(p.color.resolvingTint(node.environment)) }
            if let p = paint, case .semanticAlpha(let name, _) = p.color, name == "tint" { paint = p.withColor(p.color.resolvingTint(node.environment)) }
            // #54: an animated colour or line width (the presented paint) replaces the evaluated one.
            if let presented = node.presentedPaint, var p = paint {
                if let c = presented.color { p = p.withColor(c) }
                if p.kind == .stroke, let w = presented.lineWidth { p = p.withLineWidth(CGFloat(w)) }
                paint = p
            }
            shape = ResolvedShape(geometry: node.presentedGeometry ?? resolvedShape.geometry, paint: paint)
        }
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
        var rowStyle: ListRowStyle?
        if case .modifier(.listRowSeparator(let visibility)) = kind { rowStyle = ListRowStyle(separatorHidden: visibility == .hidden) }
        if case .modifier(.listRowBackground(let background)) = kind { rowStyle = background.style }
        var shortcut: ResolvedShortcut?
        if case .modifier(.keyboardShortcut(let key, let modifiers)) = kind {
            shortcut = ResolvedShortcut(
                chord: KeyboardChord(key: key, modifiers: modifiers),
                logical: KeyboardChords.command(for: key, modifiers: modifiers, on: keyboardPlatform)
            )
        }
        var slider: ResolvedSlider?
        if case .slider(let spec) = kind { slider = resolveSlider(node, spec: spec) }
        var rotation: ResolvedRotation?
        if case .modifier(.rotation(let angle, let anchor)) = kind { rotation = ResolvedRotation(angle: angle, anchor: anchor) }
        var brightness: Double?
        if case .modifier(.brightness(let amount)) = kind { brightness = amount }
        var clipShape: ResolvedClipShape?
        if case .modifier(.clipShape(let geometry, let fillStyle)) = kind { clipShape = ResolvedClipShape(geometry: node.presentedGeometry ?? geometry, fillStyle: fillStyle) }
        // R5: a Text shrunk by `minimumScaleFactor` draws with the font that produced its placed size.
        var style = node.style
        // The placed frame is snapped to device pixels, the memoised size is not (CI 39579395357: the exact comparison never matched with the real measurer, the
        // host painted the unshrunk font and found no measured run for the bounds): the memoised size nearest the exact placed rect, within one device pixel.
        let pixel = 1 / max(scale, 1e-6) + 1e-6
        if case .text = kind, !node.memoScaledFont.isEmpty,
           let width = node.memoScaledFont.keys.compactMap({ key -> (key: CGFloat?, distance: CGFloat)? in
               guard let size = node.memo[key] else { return nil }
               let dw = abs(size.width - node.exactFrame.width), dh = abs(size.height - node.exactFrame.height)
               return dw <= pixel && dh <= pixel ? (key, dw + dh) : nil
           }).min(by: { ($0.distance, $0.key ?? .infinity) < ($1.distance, $1.key ?? .infinity) })?.key,
           let shrunk = node.memoScaledFont[width] {
            style = ResolvedStyle(font: shrunk, foreground: style.foreground, colorScheme: style.colorScheme)
        }
        // #54: an animated foreground style (a node whose paint is its foreground: not a `Color` view, not a shape with its own paint).
        if let presented = node.presentedPaint?.color {
            var paintIsForeground = true
            switch kind {
            case .color: paintIsForeground = false
            case .shape(let s): paintIsForeground = s.paint == nil
            default: break
            }
            if paintIsForeground, style.foreground != nil { style = ResolvedStyle(font: style.font, foreground: presented, colorScheme: style.colorScheme) }
        }
        if case .modifier(.spinner(let steps, let period)) = kind { rotation = ResolvedRotation(angle: .degrees(360 * Double(spinnerStep(steps: steps, period: period) % max(steps, 1)) / Double(max(steps, 1))), anchor: .center) }
        var gradient: ResolvedGradient?
        if case .gradient(let resolvedGradient) = kind { gradient = resolvedGradient.resolvingTint(node.environment) }
        var scaleEffect: ResolvedScale?
        if case .modifier(.scale(let x, let y, let anchor)) = kind {
            let presented = node.presentedScale ?? CGSize(width: x, height: y)
            scaleEffect = ResolvedScale(x: presented.width, y: presented.height, anchor: anchor)
        }
        var resolvedNode = ResolvedNode(
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
            style: style,
            image: image,
            imageSizing: imageSizing,
            color: color,
            shapeStorage: shape.map(ResolvedShapeStorage.init),
            menu: node.menuEntries.map(resolveMenu),
            presentation: node.presented.map(resolvePresentation),
            shortcut: shortcut,
            buttonStyle: buttonStyle,
            isDefaultButton: isDefaultButton,
            listStyle: listStyle,
            rowStyle: rowStyle,
            slider: slider,
            scroll: node.scrollState,
            rotation: rotation,
            scaleEffect: scaleEffect,
            brightness: brightness,
            clipShape: clipShape,
            exactFrame: node.motion == nil && node.exactFrame != node.frame && node.exactFrame != .zero ? node.exactFrame : nil,
            scaleLocalFrame: node.motion == nil ? node.scaleLocalFrame : nil,
            styledText: styledText(of: node)
        )
        resolvedNode.gradient = gradient
        resolvedNode.numericRoll = resolveNumericRoll(node, style: style, text: text)
        // #54: a control reads the environment's tint where it paints its accent (a prominent Button's fill, a Toggle's on state, a Slider's fill).
        switch kind {
        case .button, .toggle, .slider: resolvedNode.tint = node.environment.tint
        default: break
        }
        return resolvedNode
    }

    /// Role, label and value for the accessibility backend. A primitive sets the role; a List's direct children
    /// are list items; an accessibilityLabel modifier overrides the label of its own node.
    private func accessibility(of node: Node, children: [ResolvedNode], selected: Bool) -> ResolvedAccessibility {
        var role: String?
        var label: String?
        var value: String?
        var hint: String?
        var isHidden = false
        var childBehavior: String?
        var addedTraits: [String] = [], removedTraits: [String] = []
        switch node.kind {
        case .text(let string):
            role = "static-text"
            label = node.environment.textCase?.apply(string) ?? string
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
        case .slider(let spec):
            role = "slider"
            value = Self.sliderValueText(spec.clamped(spec.read()))
        case .image(let spec):
            role = "image"
            label = spec.labelText ?? spec.reference.accessibilityName
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
        case .modifier(.accessibilityValue(let given)):
            value = given
        case .modifier(.accessibilityHint(let given)):
            hint = given
        case .modifier(.accessibilityHidden(let hide)):
            isHidden = hide
        case .modifier(.accessibilityElement(let behavior)):
            childBehavior = behavior.name
        case .modifier(.accessibilityTraits(let traits, let add)):
            if add { addedTraits = traits.names } else { removedTraits = traits.names }
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
            isSelected: selected,
            hint: hint, isHidden: isHidden, childBehavior: childBehavior, addedTraits: addedTraits, removedTraits: removedTraits,
            allowsHitTesting: node.environment.allowsHitTesting
        )
    }

    /// The accessibility value of a slider as text: an integral value without a fraction ("40"), else the shortest decimal.
    static func sliderValueText(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
    }

    /// Accessibility title of a labelled control (TextField, Toggle, Slider), from its label view.
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
        case .slider: return "SliderControl"
        case .image: return "Image"
        case .color: return "Color"
        case .gradient: return "Gradient"
        case .shape(let shape):
            return shape.geometry.kindName
        case .textEditor: return "TextEditor"
        case .divider: return "Divider"
        case .menu: return "Menu"
        }
    }
}
