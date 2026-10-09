import Foundation
import Observation

// MARK: - Identity

/// One step of a structural path. Positional segments come from the builder (tuple index,
/// Either branch, Optional presence); keyed segments come from explicit ForEach ids.
enum Segment: Hashable, CustomStringConvertible {
    case type(String)        // leaf view type (full name, identity); displayed short
    case index(Int)          // position inside a builder tuple
    case branch(Int)         // ConditionalContent arm
    case optional            // Optional<View> presence
    case keyed(AnyHashable)  // ForEach explicit id

    var description: String {
        switch self {
        case .type(let name): return shortName(name)
        case .index(let i): return "#\(i)"
        case .branch(let i): return "branch\(i)"
        case .optional: return "opt"
        case .keyed(let value): return "[\(value)]"
        }
    }
}

func shortName(_ fullName: String) -> String {
    let head = fullName.prefix { $0 != "<" }
    return String(head.split(separator: ".").last ?? Substring(head))
}

public struct NodeID: Hashable, CustomStringConvertible {
    let segments: [Segment]
    public var description: String { segments.map(\.description).joined(separator: "/") }
}

// MARK: - Node

/// Type-erased focus binding of one `.focused(_:equals:)` modifier.
@MainActor
struct FocusLink {
    /// True when the bound focus names this modifier's value.
    let isFocused: () -> Bool
    /// Makes this modifier's value the focus.
    let focus: () -> Void
    /// Clears the focus only while it still names this modifier's value.
    let release: () -> Void
}

enum ModifierSpec {
    case padding(EdgeInsets)
    case appear(() -> Void)
    case disappear(() -> Void)
    /// `id` is nil for `task(name:...)`; a non-nil id restarts the task when it changes.
    case task(TaskPriority, AnyEquatable?, @isolated(any) () async -> Void)
    case focus(FocusLink)
    case animation(AnyEquatable, Animation?)
    case environment((inout EnvironmentValues) -> Void)
    case opacity(Double)
    /// SR1: `.tag(_:)` value of a List row.
    case tag(AnyHashable)
    /// SR1: the `onDelete` hook of a List row.
    case deletion(DeletionHook)
    /// SR1: a context menu's content, evaluated into `Node.menuEntries`.
    case contextMenu(any View)
    /// SR1: an alert or confirmation dialog, presented while its binding is true.
    case presentation(PresentationPayload)
    case keyboardShortcut(KeyEquivalent, EventModifiers)
    case accessibilityLabel(String)

    var name: String {
        switch self {
        case .padding: return "padding"
        case .appear: return "onAppear"
        case .disappear: return "onDisappear"
        case .task: return "task"
        case .focus: return "focused"
        case .animation: return "animation"
        case .environment: return "environment"
        case .opacity: return "opacity"
        case .tag: return "tag"
        case .deletion: return "onDelete"
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
    case modifier(ModifierSpec)
    /// SR1 controls. Toggle keeps its label as the child; the others are leaves or model-only.
    case toggle(Binding<Bool>)
    case image(ImageReference)
    case textEditor(Binding<String>)
    case divider
    /// Menu label is the child; its items are a model (`Node.menuEntries`).
    case menu

    /// Wrappers whose geometry is their single child's geometry (user bodies, buttons, and
    /// modifiers other than padding).
    var passesThrough: Bool {
        switch self {
        case .user, .button: return true
        case .modifier(.padding): return false
        case .modifier: return true
        default: return false
        }
    }
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

/// Weak link from owner tokens and observation callbacks to a node. Holding a handle never keeps
/// a node alive, which is what lets a torn-down tree be released.
@MainActor
final class NodeHandle {
    weak var node: Node?
}

@MainActor
final class Node {
    let id: NodeID
    let handle: NodeHandle
    weak var parent: Node?
    var view: any View
    var inherited = EnvironmentValues()
    var environment = EnvironmentValues()
    var children: [NodeID] = []
    var storage: [String: AnyObject] = [:]
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
    /// Target opacity (own `.opacity` times the parent's target).
    var targetOpacity: Double = 1
    /// Presented (animated) values: what the last commit showed.
    var presentedFrame: LayoutRect = .zero
    var presentedOpacity: Double = 1
    /// False until the first commit presents this node.
    var committed = false
    /// Running interpolation of `presentedFrame` and `presentedOpacity`.
    var motion: Motion?
    /// Per-field text input state (TextField and TextEditor nodes only).
    var textInput: TextInputState?
    /// Font identifier of the last measurement (the memo is keyed by text, font and width).
    var memoFont: String?
    /// Selection binding of a List node, set at evaluation.
    var selection: SelectionAccess?
    /// Anchor and cursor of a List's keyboard and click selection, as row tags.
    var selectionAnchor: AnyHashable?
    var selectionCursor: AnyHashable?
    /// Items of a Menu or context menu, evaluated at each evaluation. Nil for other nodes.
    var menuEntries: [MenuEntry]?
    /// The presented alert or dialog, while presented. Nil otherwise.
    var presented: PresentedModel?

    init(id: NodeID, view: any View, parent: Node?) {
        self.id = id
        self.view = view
        self.parent = parent
        handle = NodeHandle()
        handle.node = self
    }

    var kind: NodeKind { (view as? PrimitiveView)?.nodeKind ?? .user }
    var depth: Int { id.segments.count }

    var retainsRemovedRowState: Bool {
        if case .stack(let spec) = kind { return spec.retainsRemovedRowState }
        return false
    }

    /// Drops everything the node owns, so that a removed node cannot keep its @State, environment,
    /// view values (and the closures in them) or observation state alive.
    func releaseContents() {
        children = []
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
    }
}

/// Keyed (ForEach) segment anywhere in a path.
private func hasKeyedSegment(_ segments: ArraySlice<Segment>) -> Bool {
    segments.contains { segment in
        if case .keyed = segment { return true }
        return false
    }
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
    /// Role, label, value, enablement and selection for the accessibility backend.
    public let accessibility: ResolvedAccessibility
    /// Font and foreground colour in effect at this node (inherited through the environment).
    public let style: ResolvedStyle
    /// Image nodes only: the reference the backend loads.
    public let image: ImageReference?
    /// Menu and context-menu nodes only: the items, with disabled state and submenus.
    public let menu: [ResolvedMenuItem]?
    /// Alert and confirmation dialog nodes, while presented.
    public let presentation: ResolvedPresentation?
    /// Modifier nodes created by `.keyboardShortcut(_:modifiers:)`.
    public let shortcut: ResolvedShortcut?
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
}

public struct CommitRecord: Equatable, Sendable {
    public let sequence: Int
    /// Nil only in the final record emitted by `tearDown()`.
    public let root: ResolvedNode?
    public let focused: String?
    /// Animation names requested by transactions that contributed to this flush, joined by ",".
    public let animation: String?
}

// MARK: - Graph

@MainActor
public final class Graph {
    typealias Entry = ([Segment], any View)

    private(set) var root: Node?
    var nodes: [NodeID: Node] = [:]
    private var dirty: [NodeID: Node] = [:]
    private var flushScheduled = false
    private var sequence = 0
    private var instanceCounter = 0
    /// Host-supplied time in seconds, set by `tick(now:)`. Animations start at this time.
    var clock: Double = 0
    private var closed = false
    let measurer: any TextMeasurer
    /// Physical pixels per logical point.
    let scale: CGFloat
    /// Size proposal for the root view. A host sets this to its content size.
    public var rootProposal: ProposedViewSize = .unspecified
    public var commitSink: ((CommitRecord) -> Void)?
    /// Intrinsic size of an image reference, in logical points. A host supplies the real size; the default is 24 pt.
    public var imageIntrinsicSize: (ImageReference) -> LayoutSize = { _ in LayoutSize(width: 24, height: 24) }
    /// Platform used to map native chords to logical commands (CONTRACT section 4).
    public var keyboardPlatform: KeyboardPlatform = .mac
    /// Models macOS System Settings > Keyboard > "Keyboard navigation" turned on: Tab also stops on focus-bound
    /// Buttons and Toggles. Default false (text fields and lists only). See FocusTraversal.swift.
    public var tabFocusesAllControls = false

    public init(_ rootView: some View, measurer: (any TextMeasurer)? = nil, scale: CGFloat = 1) {
        self.measurer = measurer ?? FixedAdvanceTextMeasurer()
        self.scale = scale
        let node = Node(id: NodeID(segments: [.type("Root")]), view: rootView, parent: nil)
        node.instance = 0
        root = node
        nodes[node.id] = node
        evaluate(node)
    }

    // MARK: Public test surface

    /// Applies pending invalidations (coalesced), lays out, and always emits one commit record.
    public func flush() {
        var rounds = 0
        while !dirty.isEmpty, rounds < 64 {
            rounds += 1
            let batch = dirty.values.sorted {
                ($0.depth, $0.id.description) < ($1.depth, $1.id.description)
            }
            dirty.removeAll()
            var evaluated: Set<NodeID> = []
            for node in batch where node.alive && nodes[node.id] === node {
                if hasEvaluatedAncestor(node, evaluated) { continue }
                evaluated.insert(node.id)
                evaluate(node)
            }
        }
        commit()
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
    /// offset is clamped to the content.
    public func scroll(_ id: String, to offset: CGFloat) {
        node(id)?.scrollOffset = offset
    }

    /// The last laid-out scroll offset of a live ScrollView.
    public func scrollOffset(_ id: String) -> CGFloat? {
        node(id).map(\.scrollOffset)
    }

    /// Edits the root environment (for example a host feeds the OS reduce-motion setting) and
    /// re-evaluates the whole tree at the next flush.
    public func setRootEnvironment(_ update: (inout EnvironmentValues) -> Void) {
        guard let root else { return }
        var environment = root.inherited
        update(&environment)
        root.inherited = environment
        dirty[root.id] = root
    }

    /// Advances animations to `now` (host-supplied seconds, monotonic). Emits one commit record when
    /// any animation was running, so the host can draw the interpolated values.
    public func tick(now: Double) {
        guard !closed, root != nil else { return }
        let wasAnimating = orderedNodes().contains { $0.motion != nil }
        clock = now
        advanceMotions(now: now)
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
        nodes.removeAll()
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
        nodes.values.first { $0.id.description == id }
    }

    /// Live nodes in a stable order (by path), so completion order does not depend on hashing.
    func orderedNodes() -> [Node] {
        nodes.values.map { (key: $0.id.description, node: $0) }
            .sorted { $0.key < $1.key }
            .map(\.node)
    }

    // MARK: Expansion and reconciliation

    private func expand(_ view: any View, prefix: [Segment], into out: inout [Entry]) {
        if view is EmptyView { return }
        if let container = view as? any ViewContainer {
            for (segment, part) in container.parts() {
                expand(part, prefix: prefix + [segment], into: &out)
            }
            return
        }
        let mirror = Mirror(reflecting: view)
        if mirror.displayStyle == .optional {
            if let child = mirror.children.first?.value as? any View {
                expand(child, prefix: prefix + [.optional], into: &out)
            }
            return
        }
        out.append((prefix + [.type(String(reflecting: type(of: view)))], view))
    }

    private func reconcile(_ parent: Node, entries: [Entry]) {
        var order: [NodeID] = []
        var viewByID: [NodeID: any View] = [:]
        for (segments, view) in entries {
            let childID = NodeID(segments: parent.id.segments + segments)
            if viewByID[childID] != nil { continue }  // duplicate ForEach id: first wins
            order.append(childID)
            viewByID[childID] = view
        }
        let surviving = Set(order)
        for old in parent.children where !surviving.contains(old) {
            if parent.retainsRemovedRowState, hasKeyedSegment(old.segments.dropFirst(parent.id.segments.count)) {
                parent.rowCache.beginRetiring(old)
                teardown(old, retainingIn: (list: parent, top: old))
                parent.rowCache.trim()
            } else {
                teardown(old)
            }
        }
        parent.children = order
        for childID in order {
            guard let view = viewByID[childID] else { continue }
            if let existing = nodes[childID] {
                existing.view = view
                existing.inherited = parent.environment
                evaluate(existing)
            } else {
                let created = Node(id: childID, view: view, parent: parent)
                instanceCounter += 1
                created.instance = instanceCounter
                created.inherited = parent.environment
                if let list = rowListAncestor(of: parent) {
                    if let restored = list.rowCache.take(childID) { created.storage = restored }
                    created.restoreFocus = list.rowCache.takeFocus(childID)
                }
                nodes[childID] = created
                evaluate(created)
                if created.restoreFocus { restoreFocus(created) }
            }
        }
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
        node.alive = false
        node.generation += 1
        dirty[id] = nil
        if node.appeared {
            node.appeared = false
            if case .modifier(.disappear(let action)) = node.kind { action() }
        }
        node.task?.cancel()
        node.task = nil
        if let motion = node.motion {
            node.motion = nil
            motion.transaction.motionEnded()
        }
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

    private func runAppear(_ node: Node) {
        guard case .modifier(let spec) = node.kind else { return }
        switch spec {
        case .appear(let action):
            action()
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
        for child in Mirror(reflecting: node.view).children {
            if let key = child.label, let property = child.value as? DynamicPropertyStorage {
                property.bindDynamicProperty(to: node, key: key)
            }
        }
    }

    func textInputState(for node: Node, binding: Binding<String>, multiline: Bool) -> TextInputState {
        if let state = node.textInput {
            state.binding = binding
            return state
        }
        let state = TextInputState(binding: binding, multiline: multiline)
        node.textInput = state
        return state
    }

    /// Evaluates one node: applies its environment override, runs appear once, restarts a
    /// `task(id:)` whose id changed, reads its dependencies under observation tracking, then
    /// reconciles its children.
    func evaluate(_ node: Node) {
        guard node.alive else { return }
        node.environment = node.inherited
        if case .modifier(.environment(let apply)) = node.kind {
            apply(&node.environment)
        }
        if !node.appeared {
            node.appeared = true
            runAppear(node)
        } else if case .modifier(.task(let priority, let id?, let action)) = node.kind,
                  let previous = node.taskID, !previous.matches(id.value) {
            node.taskID = id
            startTask(node, priority, action)
        }
        if case .modifier(.animation(let value, let animation)) = node.kind {
            if let previous = node.lastEquatable, !previous.matches(value.value) {
                TransactionContext.enqueue(AnimationTransaction(animation: animation, completion: nil))
            }
            node.lastEquatable = value
        }
        if case .user = node.kind { bindDynamicProperties(node) }
        node.selection = (node.view as? SelectionProviding)?.selectionAccess
        if case .textField(let binding) = node.kind {
            _ = textInputState(for: node, binding: binding, multiline: false)
        }
        if case .textEditor(let binding) = node.kind {
            _ = textInputState(for: node, binding: binding, multiline: true)
        }

        let produced: (any View)? = withObservationTracking({
            switch node.kind {
            case .textField, .textEditor: _ = node.textInput?.display
            case .modifier(.focus(let link)): node.focused = link.isFocused()
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
            if let primitive = node.view as? PrimitiveView { return primitive.nodeContent }
            return node.view.evaluateBody()
        }, onChange: { [weak self, handle = node.handle] in
            // Weak on purpose: a pending observation must not keep the graph or its nodes alive.
            MainActor.assumeIsolated {
                if let node = handle.node { self?.noteChange(node) }
            }
        })

        var entries: [Entry] = []
        if let produced { expand(produced, prefix: [], into: &entries) }
        reconcile(node, entries: entries)
    }

    // MARK: Invalidation

    func noteChange(_ node: Node) {
        guard node.alive, nodes[node.id] === node else { return }
        dirty[node.id] = node
        scheduleFlush()
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

    private func hasEvaluatedAncestor(_ node: Node, _ evaluated: Set<NodeID>) -> Bool {
        var current = node.parent
        while let ancestor = current {
            if evaluated.contains(ancestor.id) { return true }
            current = ancestor.parent
        }
        return false
    }

    // MARK: Commit

    private func commit() {
        guard !closed, let root else { return }
        advanceMotions(now: clock)
        let previous: [NodeID: (LayoutRect, Double)] = nodes.mapValues { ($0.frame, $0.targetOpacity) }
        layoutRoot()
        assignOpacity(root, parent: 1)
        let changed = orderedNodes().filter { node in
            guard let before = previous[node.id] else { return true }
            return before.0 != node.frame || before.1 != node.targetOpacity
        }
        let transactions = TransactionContext.takeQueued()
        applyTransactions(transactions, changed: changed)
        emit(animationNames: transactions.compactMap { $0.animation?.name })
        TransactionContext.drainDeferred()
    }

    /// Builds and delivers one commit record from the presented values.
    private func emit(animationNames: [String]) {
        guard let root else { return }
        sequence += 1
        let focusedNode = nodes.values.filter { $0.focused && $0.alive }.min { $0.id.description < $1.id.description }
        let record = CommitRecord(
            sequence: sequence,
            root: resolve(root),
            focused: focusedNode?.id.description,
            animation: animationNames.isEmpty ? nil : animationNames.joined(separator: ",")
        )
        commitSink?(record)
    }

    private func resolve(_ node: Node, selected: Bool = false) -> ResolvedNode {
        let text: String?
        var selection: UTF16Range?
        var marked: UTF16Range?
        switch node.kind {
        case .text(let string):
            text = string
        case .textField, .textEditor:
            text = node.textInput?.display
            selection = node.textInput?.selection
            marked = node.textInput?.markedRange
        default:
            text = nil
        }
        let selectedTags = node.selection?.current() ?? []
        let children: [ResolvedNode] = node.children.compactMap { childID in
            guard let child = nodes[childID] else { return nil }
            let isSelected = node.selection != nil && (tagOf(child).map { selectedTags.contains($0) } ?? false)
            return resolve(child, selected: isSelected)
        }
        var image: ImageReference?
        if case .image(let reference) = node.kind { image = reference }
        var shortcut: ResolvedShortcut?
        if case .modifier(.keyboardShortcut(let key, let modifiers)) = node.kind {
            shortcut = ResolvedShortcut(
                chord: KeyboardChord(key: key, modifiers: modifiers),
                logical: KeyboardChords.command(for: key, modifiers: modifiers, on: keyboardPlatform)
            )
        }
        return ResolvedNode(
            id: node.id.description,
            kind: kindName(node),
            text: text,
            frame: node.presentedFrame,
            pixelFrame: pixelRect(node.presentedFrame, scale: scale),
            opacity: node.presentedOpacity,
            selection: selection,
            marked: marked,
            children: children,
            accessibility: accessibility(of: node, children: children, selected: selected),
            style: ResolvedStyle(font: node.environment.font, foreground: node.environment.foregroundStyle),
            image: image,
            menu: node.menuEntries.map(resolveMenu),
            presentation: node.presented.map(resolvePresentation),
            shortcut: shortcut
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
        case .image(let reference):
            role = "image"
            label = reference.name
        case .menu:
            role = "menu"
            label = joinedText(children)
        case .divider:
            role = "separator"
        case .scroll:
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
            isEnabled: node.environment.isEnabled,
            isSelected: selected
        )
    }

    /// Accessibility title of a labelled control (TextField, Toggle), from its label view.
    private func titleOf(_ node: Node) -> String? {
        guard let labeled = node.view as? LabeledControl else { return nil }
        let title = ViewWalk.plainText(labeled.titleView)
        return title.isEmpty ? nil : title
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
        case .user: return shortName(String(reflecting: type(of: node.view)))
        case .text: return "Text"
        case .spacer: return "Spacer"
        case .button: return "Button"
        case .textField: return "TextField"
        case .stack(let spec): return spec.name
        case .layout: return "Layout"
        case .scroll: return "ScrollView"
        case .modifier(let spec): return "modifier.\(spec.name)"
        case .toggle: return "Toggle"
        case .image: return "Image"
        case .textEditor: return "TextEditor"
        case .divider: return "Divider"
        case .menu: return "Menu"
        }
    }
}
