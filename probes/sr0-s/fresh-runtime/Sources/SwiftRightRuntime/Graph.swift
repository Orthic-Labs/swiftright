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

enum ModifierSpec {
    case padding(EdgeInsets)
    case appear(() -> Void)
    case disappear(() -> Void)
    case task(TaskPriority, @isolated(any) () async -> Void)
    case focus(() -> Bool)
    case animation(AnyEquatable, Animation?)
    case environment((inout EnvironmentValues) -> Void)

    var name: String {
        switch self {
        case .padding: return "padding"
        case .appear: return "onAppear"
        case .disappear: return "onDisappear"
        case .task: return "task"
        case .focus: return "focused"
        case .animation: return "animation"
        case .environment: return "environment"
        }
    }
}

enum NodeKind {
    case user
    case text(String)
    case spacer(CGFloat)
    case button(() -> Void)
    case textField(() -> String)
    case stack(StackSpec)
    case layout(LayoutSpec)
    case modifier(ModifierSpec)

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

@MainActor
final class Node {
    let id: NodeID
    weak var parent: Node?
    var view: any View
    var inherited = EnvironmentValues()
    var environment = EnvironmentValues()
    var children: [NodeID] = []
    var storage: [String: AnyObject] = [:]
    var alive = true
    var appeared = false
    /// Bumped on teardown. Owner tokens captured before teardown stop matching.
    var generation = 0
    var focused = false
    var task: Task<Void, Never>?
    var lastEquatable: AnyEquatable?
    /// Monotonic per-graph creation number. Unlike object addresses it is never reused.
    var instance = 0
    /// Frame in logical points, snapped to the physical pixel grid at placement.
    var frame: LayoutRect = .zero
    /// Text memo: measured sizes for the current text, keyed by wrap width (nil = no wrap).
    var memoText: String?
    var memo: [CGFloat?: LayoutSize] = [:]
    /// Cache owned by a custom `Layout` container.
    var layoutStorage: Any?

    init(id: NodeID, view: any View, parent: Node?) {
        self.id = id
        self.view = view
        self.parent = parent
    }

    var kind: NodeKind { (view as? PrimitiveView)?.nodeKind ?? .user }
    var depth: Int { id.segments.count }
}

/// Guarded commit for async work started by `.task`. A commit is accepted only while the
/// owning node is alive and still has the generation the task was started under.
public struct TaskOwnerToken: Sendable {
    fileprivate let node: Node
    fileprivate let generation: Int

    @MainActor
    public var isLive: Bool { node.alive && node.generation == generation }

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
    public let text: String?
    /// Logical points, edges snapped to the physical pixel grid.
    public let frame: LayoutRect
    /// The same frame in physical device pixels.
    public let pixelFrame: PixelRect
    public let children: [ResolvedNode]
}

public struct CommitRecord: Equatable, Sendable {
    public let sequence: Int
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
    private var pendingAnimations: [String] = []
    private var flushScheduled = false
    private var sequence = 0
    private var instanceCounter = 0
    let measurer: any TextMeasurer
    /// Physical pixels per logical point.
    let scale: CGFloat
    /// Size proposal for the root view. A host sets this to its content size.
    public var rootProposal: ProposedViewSize = .unspecified
    public var commitSink: ((CommitRecord) -> Void)?

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
        root.map(resolve)
    }

    /// Creation number of the live node at `id`. Equal numbers mean the same node instance;
    /// a removed-then-reinserted row gets a new number.
    public func nodeInstance(_ id: String) -> Int? {
        nodes.values.first { $0.id.description == id }?.instance
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
        guard let node = nodes.values.first(where: { $0.id.description == id }),
              case .button(let action) = node.kind else { return false }
        action()
        return true
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
            teardown(old)
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
                nodes[childID] = created
                evaluate(created)
            }
        }
    }

    private func teardown(_ id: NodeID) {
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
        for child in node.children { teardown(child) }
        node.children = []
    }

    private func runAppear(_ node: Node) {
        guard case .modifier(let spec) = node.kind else { return }
        switch spec {
        case .appear(let action):
            action()
        case .task(let priority, let action):
            let token = TaskOwnerToken(node: node, generation: node.generation)
            node.task = Task(priority: priority) {
                await TaskOwner.$current.withValue(token) {
                    await action()
                }
            }
        default:
            break
        }
    }

    private func bindDynamicProperties(_ node: Node) {
        for child in Mirror(reflecting: node.view).children {
            if let key = child.label, let property = child.value as? DynamicPropertyStorage {
                property.bindDynamicProperty(to: node, key: key)
            }
        }
    }

    /// Evaluates one node: applies its environment override, runs appear once, reads its
    /// dependencies under observation tracking, then reconciles its children.
    func evaluate(_ node: Node) {
        guard node.alive else { return }
        node.environment = node.inherited
        if case .modifier(.environment(let apply)) = node.kind {
            apply(&node.environment)
        }
        if !node.appeared {
            node.appeared = true
            runAppear(node)
        }
        if case .modifier(.animation(let value, let animation)) = node.kind {
            if let previous = node.lastEquatable, !previous.matches(value.value), let animation {
                pendingAnimations.append(animation.name)
            }
            node.lastEquatable = value
        }
        if case .user = node.kind { bindDynamicProperties(node) }

        let produced: (any View)? = withObservationTracking({
            switch node.kind {
            case .textField(let read): _ = read()
            case .modifier(.focus(let predicate)): node.focused = predicate()
            default: break
            }
            if let primitive = node.view as? PrimitiveView { return primitive.nodeContent }
            return node.view.evaluateBody()
        }, onChange: { [self, node] in
            MainActor.assumeIsolated { self.noteChange(node) }
        })

        var entries: [Entry] = []
        if let produced { expand(produced, prefix: [], into: &entries) }
        reconcile(node, entries: entries)
    }

    // MARK: Invalidation

    func noteChange(_ node: Node) {
        guard node.alive, nodes[node.id] === node else { return }
        dirty[node.id] = node
        if let animation = TransactionContext.current {
            pendingAnimations.append(animation.name)
        }
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
        layoutRoot()
        sequence += 1
        let focusedNode = nodes.values.filter { $0.focused && $0.alive }.min { $0.id.description < $1.id.description }
        let record = CommitRecord(
            sequence: sequence,
            root: root.map(resolve),
            focused: focusedNode?.id.description,
            animation: pendingAnimations.isEmpty ? nil : pendingAnimations.joined(separator: ",")
        )
        pendingAnimations.removeAll()
        commitSink?(record)
    }

    private func resolve(_ node: Node) -> ResolvedNode {
        let text: String?
        switch node.kind {
        case .text(let string): text = string
        case .textField(let read): text = read()
        default: text = nil
        }
        return ResolvedNode(
            id: node.id.description,
            kind: kindName(node),
            text: text,
            frame: node.frame,
            pixelFrame: pixelRect(node.frame, scale: scale),
            children: node.children.compactMap { nodes[$0].map(resolve) }
        )
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
        case .modifier(let spec): return "modifier.\(spec.name)"
        }
    }
}

// MARK: - Transactions

@MainActor
enum TransactionContext {
    /// Animation attached to invalidations raised inside `withAnimation`; nil outside.
    static var current: Animation?
}

public struct Animation: Sendable, Equatable {
    public let name: String
    public init() { name = "default" }
    public init(name: String) { self.name = name }
    public static let `default` = Animation()
}

@MainActor
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    let previous = TransactionContext.current
    TransactionContext.current = animation
    defer { TransactionContext.current = previous }
    return try body()
}
