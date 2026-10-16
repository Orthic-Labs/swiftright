import Foundation

// Animation semantics (SR0-S F6 oracle, headless form; curves, layering, completion and scoping measured on macOS SwiftUI, SR1 round 3 lane C).
//
// A transaction is created by `withAnimation` / `withTransaction` or by a changed `.animation(_:value:)`, and is queued. The next commit drains
// the queue and applies it to every node whose layout target or target opacity changed in that flush:
//   - an explicit transaction (withAnimation / withTransaction) applies to every changed node; the last one queued in a flush wins and the
//     earlier ones finish at once. A changed `.animation(_:value:)` applies only to the nodes below that modifier, and the innermost one wins
//     over the explicit transaction (a `nil` animation snaps). `Transaction.disablesAnimations` makes the modifiers yield to the explicit one.
//   - an animated transaction starts a LAYER on the node. Layers blend: the presented value is
//     `P_j(t) = lerp(P_(j-1)(t), target_j, curve_j(t - start_j))`, so an interrupted animation keeps running underneath the new one until its
//     own end (SwiftUI's additive interruption; the measured inst 1 / inst 2 delta = target_2 - P_1(t)). A built-in spring that interrupts a
//     spring merges instead: the new spring continues from the presented position and velocity.
//   - a nil animation, a reduce-motion node or a zero duration snaps to the target; a newly inserted node starts from its transition's
//     initial state (`.opacity` unless a `.transition` modifier says otherwise) and animates to its target under an animated transaction.
// Layers advance only through `Graph.tick(now:)` (host clock). A layer begins at the first tick after it was created: that tick is its progress 0,
// whatever the host clock reads. A flush between ticks never begins, advances or ends a layer.
// Completion (`withAnimation(_:completionCriteria:_:completion:)`): `.logicallyComplete` fires when every layer the transaction started has
// reached its logical duration (for the default spring 0.5 s, although it settles later: see `SpringModel`); `.removed` fires when the node's whole chain
// of layers has finished and been removed. A transaction that started no layer (no change, nil animation) completes at its commit.
// Completions run after the commit record has been delivered.

/// A timing curve over normalized time.
public struct Animation: Sendable, Equatable {
    public enum Curve: Sendable, Equatable {
        case linear
        case easeIn
        case easeOut
        case easeInOut
        /// SwiftUI's default spring (`Animation.default`, `.smooth`, `.spring`: duration 0.5, bounce 0), tabulated from SwiftUI on macOS 27.
        case spring
    }

    /// Tag recorded in commit records.
    public let name: String
    /// Seconds. For a spring the perceptual duration, at which `.logicallyComplete` fires.
    public let duration: Double
    public let curve: Curve

    /// SwiftUI's `.default`: a spring of 0.5 s and no bounce (measured: `Animation.default`, `.smooth` and `.spring` evaluate identically).
    public init() {
        self.init(name: "default", duration: 0.5, curve: .spring)
    }

    public init(name: String, duration: Double = 0.35, curve: Curve = .easeInOut) {
        self.name = name
        self.duration = duration
        self.curve = curve
    }

    public static let `default` = Animation()

    public static func linear(duration: Double) -> Animation {
        Animation(name: "linear", duration: duration, curve: .linear)
    }

    public static func easeIn(duration: Double) -> Animation {
        Animation(name: "easeIn", duration: duration, curve: .easeIn)
    }

    public static func easeOut(duration: Double) -> Animation {
        Animation(name: "easeOut", duration: duration, curve: .easeOut)
    }

    public static func easeInOut(duration: Double) -> Animation {
        Animation(name: "easeInOut", duration: duration, curve: .easeInOut)
    }

    /// 0.35 s, as SwiftUI.
    public static var linear: Animation { linear(duration: 0.35) }
    public static var easeIn: Animation { easeIn(duration: 0.35) }
    public static var easeOut: Animation { easeOut(duration: 0.35) }
    public static var easeInOut: Animation { easeInOut(duration: 0.35) }
    /// The same spring as `.default`.
    public static var smooth: Animation { Animation(name: "smooth", duration: 0.5, curve: .spring) }
    public static var spring: Animation { Animation(name: "spring", duration: 0.5, curve: .spring) }

    /// Seconds until the layer stops changing the presentation and is removed. A spring settles when what is left of each animated component is under
    /// SwiftUI's one-device-pixel tolerance, so its end depends on the distance and the display scale: `MotionLayer.visualDuration` computes it.
    var visualDuration: Double { duration }
}

/// How `withAnimation(_:completionCriteria:_:completion:)` decides the animation is complete.
public struct AnimationCompletionCriteria: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case logicallyComplete, removed }
    let kind: Kind
    /// Complete when the animation has run for its logical duration (a spring: its perceptual duration).
    public static let logicallyComplete = AnimationCompletionCriteria(kind: .logicallyComplete)
    /// Complete when the animation has finished and been removed from the presentation (a spring: when it has settled).
    public static let removed = AnimationCompletionCriteria(kind: .removed)
}

/// Unit cubic Bezier (CSS style control points), solved for y at a given x.
struct UnitBezier {
    let ax: Double, bx: Double, cx: Double, ay: Double, by: Double, cy: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        cx = 3 * x1; bx = 3 * (x2 - x1) - cx; ax = 1 - cx - bx
        cy = 3 * y1; by = 3 * (y2 - y1) - cy; ay = 1 - cy - by
    }

    private func x(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func y(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func dx(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    func value(at x0: Double) -> Double {
        if x0 <= 0 { return 0 }
        if x0 >= 1 { return 1 }
        var t = x0
        for _ in 0..<8 {
            let err = x(t) - x0
            if abs(err) < 1e-12 { return y(t) }
            let d = dx(t)
            if abs(d) < 1e-9 { break }
            t -= err / d
        }
        var lo = 0.0, hi = 1.0
        t = x0
        while lo < hi {
            let err = x(t)
            if abs(err - x0) < 1e-12 { break }
            if x0 > err { lo = t } else { hi = t }
            let next = (hi - lo) / 2 + lo
            if next == t { break }
            t = next
        }
        return y(t)
    }

    // SwiftUI's built-in curves, identical to `UnitCurve.easeIn/easeOut/easeInOut` and the CSS ease-in/out/in-out (measured).
    static let easeIn = UnitBezier(0.42, 0, 1, 1)
    static let easeOut = UnitBezier(0, 0, 0.58, 1)
    static let easeInOut = UnitBezier(0.42, 0, 0.58, 1)
}

/// The default spring, as measured from SwiftUI (`Animation.default` on macOS 27, evaluated at 12.5 ms steps from a fresh state, 0 to 0.8125 s).
/// A built-in spring integrates in small fixed steps, so its curve is not a closed-form spring; the table reproduces it. Between two
/// entries the value is interpolated linearly; past the last entry the remainder shrinks by `tailRatio` per step.
///
/// SwiftUI removes the animation (the value snaps to the target) at the first call where every animated component is within a tolerance of its
/// target, measured on macOS 27.0.1 (26A434) with 12.5 ms sampling, amplitudes 15 to 400 and display scales 1 to 3: width and height 1.05 / displayScale
/// pt, x and y offsets 0.5 / displayScale pt, opacity 0.0006 (no scale). The old constant 0.537 s was the 100 pt, scale 1 case (decision C11).
enum SpringModel {
    /// The perceptual duration the table was measured for.
    static let perceptual = 0.5
    static let step = 0.0125
    static let table: [Double] = [
        0.000000, 0.009937, 0.041377, 0.087193, 0.127702, 0.186574, 0.248139, 0.310082, 0.370762, 0.414751,
        0.470753, 0.523282, 0.572065, 0.606131, 0.648200, 0.686530, 0.721278, 0.745108, 0.774085, 0.800081,
        0.823335, 0.839118, 0.858136, 0.875040, 0.890036, 0.900149, 0.912263, 0.922966, 0.930158, 0.938749,
        0.946315, 0.952972, 0.957431, 0.962741, 0.967403, 0.971492, 0.974225, 0.977473, 0.980317, 0.982808,
        0.984469, 0.986440, 0.988164, 0.989671, 0.990675, 0.991865, 0.992905, 0.993812, 0.994417, 0.995132,
        0.995756, 0.996301, 0.996776, 0.997092, 0.997466, 0.997792, 0.998077, 0.998266, 0.998489, 0.998684,
        0.998854, 0.998967, 0.999100, 0.999216, 0.999317, 0.999385,
    ]
    /// What is left shrinks by this factor per step after the table (fit to the last five entries).
    static let tailRatio = 0.8836
    /// Critically damped natural frequency (rad/s) of the closest closed-form spring (fit to the table, worst error 0.01): used only when a
    /// spring continues from a velocity (an interrupted spring), where no table exists.
    static let omega = 12.658

    private static var lastIndex: Int { table.count - 1 }

    /// Progress of a spring that starts at rest, `elapsed` seconds in (perceptual duration `duration`).
    static func value(elapsed: Double, duration: Double) -> Double {
        let e = elapsed * perceptual / duration
        if e <= 0 { return 0 }
        let x = e / step
        let i = Int(x)
        if i >= lastIndex {
            return 1 - (1 - table[lastIndex]) * pow(tailRatio, x - Double(lastIndex))
        }
        let f = x - Double(i)
        return table[i] + (table[i + 1] - table[i]) * f
    }

    /// Seconds (at the perceptual duration) after which a spring across `displacement` (target minus start: x, y, width, height, opacity) is removed.
    static func settle(displacement: [Double], scale: Double) -> Double {
        let s = max(scale, 0.25)
        let tolerance = [0.5 / s, 0.5 / s, 1.05 / s, 1.05 / s, 0.0006]
        var settle = 0.0
        for i in 0..<min(displacement.count, tolerance.count) {
            let d = abs(displacement[i])
            guard d > tolerance[i] else { continue }
            settle = max(settle, time(remaining: tolerance[i] / d))
        }
        return settle
    }

    /// First time at which the share still to travel is `q` (0 < q < 1).
    private static func time(remaining q: Double) -> Double {
        let last = 1 - table[lastIndex]
        if q < last { return (Double(lastIndex) + log(q / last) / log(tailRatio)) * step }
        var i = 0
        while i < lastIndex - 1 && 1 - table[i + 1] > q { i += 1 }
        let a = 1 - table[i], b = 1 - table[i + 1]
        let f = b < a ? (a - q) / (a - b) : 0
        return (Double(i) + min(max(f, 0), 1)) * step
    }
}

extension Animation.Curve {
    /// Eased progress for normalized time `t` in 0...1 (not for `.spring`, which is a function of seconds: see `SpringModel`).
    func value(at t: Double) -> Double {
        let x = min(max(t, 0), 1)
        switch self {
        case .linear: return x
        case .easeIn: return UnitBezier.easeIn.value(at: x)
        case .easeOut: return UnitBezier.easeOut.value(at: x)
        case .easeInOut: return UnitBezier.easeInOut.value(at: x)
        case .spring: return SpringModel.value(elapsed: x * 0.5, duration: 0.5)
        }
    }
}

/// One transaction: its animation (nil = no animation) and an optional completion.
@MainActor
final class AnimationTransaction {
    let animation: Animation?
    let criteria: AnimationCompletionCriteria
    /// `Transaction.disablesAnimations`: `.animation(_:value:)` modifiers yield to this transaction.
    let disablesAnimations: Bool
    /// The `.animation(_:value:)` modifier node this transaction came from; nil for an explicit transaction.
    let scope: Node?
    private var completion: (() -> Void)?
    /// Layers this transaction started that have not yet reached their logical end / been removed.
    private(set) var logicalPending = 0
    private(set) var removalPending = 0
    private var settled = false

    init(animation: Animation?, completion: (() -> Void)?, criteria: AnimationCompletionCriteria = .logicallyComplete,
         disablesAnimations: Bool = false, scope: Node? = nil) {
        self.animation = animation
        self.completion = completion
        self.criteria = criteria
        self.disablesAnimations = disablesAnimations
        self.scope = scope
    }

    func layerStarted() {
        logicalPending += 1
        removalPending += 1
    }

    func layerLogicallyEnded() {
        logicalPending -= 1
        settleIfDone()
    }

    func layerRemoved() {
        removalPending -= 1
        settleIfDone()
    }

    /// Schedules the completion once, when no layer the completion criteria wait for is still running.
    func settleIfDone() {
        guard !settled else { return }
        guard (criteria == .removed ? removalPending : logicalPending) == 0 else { return }
        settled = true
        if let completion {
            TransactionContext.deferred.append(completion)
            self.completion = nil
        }
    }
}

/// The animated state of one node: frame and opacity.
struct Presentation {
    var frame: LayoutRect
    var opacity: Double

    static func lerp(_ a: Presentation, _ b: Presentation, _ t: Double) -> Presentation {
        if t <= 0 { return a }
        if t >= 1 { return b }
        let k = CGFloat(t)
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * k }
        return Presentation(
            frame: LayoutRect(x: mix(a.frame.minX, b.frame.minX), y: mix(a.frame.minY, b.frame.minY),
                              width: mix(a.frame.width, b.frame.width), height: mix(a.frame.height, b.frame.height)),
            opacity: a.opacity + (b.opacity - a.opacity) * t
        )
    }

    var components: [Double] {
        [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height), opacity]
    }

    init(frame: LayoutRect, opacity: Double) {
        self.frame = frame
        self.opacity = opacity
    }

    init(components c: [Double]) {
        frame = LayoutRect(x: CGFloat(c[0]), y: CGFloat(c[1]), width: CGFloat(c[2]), height: CGFloat(c[3]))
        opacity = c[4]
    }
}

/// One animation running on a node. It blends from the value below it in the chain to `to`.
@MainActor
final class MotionLayer {
    let to: Presentation
    let animation: Animation
    let transaction: AnimationTransaction
    /// Host time of progress 0. Nil until the first tick after the layer was created.
    var start: Double?
    var logicallyEnded = false
    var finished = false
    /// False for a removal transition: the removed view is still presented at exactly the end time and goes with the first tick after it (measured).
    var inclusiveEnd = true
    /// A spring that continued from an interrupted spring: displacement from `to` (target - value) and its rate of change per component.
    var continuation: (displacement: [Double], velocity: [Double])?
    /// Seconds after which a spring that starts at rest is removed (its distance and the display scale decide: `SpringModel.settle`); nil until `startLayer` sets it.
    var springSettle: Double?

    init(to: Presentation, animation: Animation, transaction: AnimationTransaction) {
        self.to = to
        self.animation = animation
        self.transaction = transaction
        transaction.layerStarted()
    }

    var isSpring: Bool { animation.curve == .spring }

    /// The value this layer contributes at `elapsed` seconds, given the value below it.
    func value(below: Presentation, elapsed: Double) -> Presentation {
        if finished { return to }
        if let continuation {
            let w = SpringModel.omega * SpringModel.perceptual / animation.duration
            let decay = exp(-w * elapsed)
            let target = to.components
            var out = target
            for i in 0..<5 {
                let d0 = continuation.displacement[i], v0 = continuation.velocity[i]
                out[i] = target[i] - (d0 + (v0 + w * d0) * elapsed) * decay
            }
            return Presentation(components: out)
        }
        let progress: Double
        if animation.curve == .spring {
            progress = SpringModel.value(elapsed: elapsed, duration: animation.duration)
        } else {
            progress = animation.curve.value(at: elapsed / animation.duration)
        }
        return Presentation.lerp(below, to, progress)
    }

    private var visualCache: Double?

    /// Seconds after which the layer is removed.
    var visualDuration: Double {
        if let visualCache { return visualCache }
        let value = computeVisualDuration()
        visualCache = value
        return value
    }

    private func computeVisualDuration() -> Double {
        guard continuation != nil else {
            if isSpring, let springSettle { return springSettle * animation.duration / SpringModel.perceptual }
            return animation.visualDuration
        }
        // a continued spring ends when every component is within 1 % of the largest starting displacement of the target
        let w = SpringModel.omega * SpringModel.perceptual / animation.duration
        let c = continuation!
        let scale = max(c.displacement.map(abs).max() ?? 0, 1e-9)
        var t = 0.0
        while t < 4 {
            let decay = exp(-w * t)
            let within = (0..<5).allSatisfy { i in abs((c.displacement[i] + (c.velocity[i] + w * c.displacement[i]) * t) * decay) <= 0.0105 * scale }
            if within { return t }
            t += 0.005
        }
        return 4
    }
}

/// The layers running on one node, bottom first. `base` is the value below the first layer.
@MainActor
final class MotionChain {
    var base: Presentation
    var layers: [MotionLayer] = []
    /// Layers that finished but whose transaction waits for the whole chain to be removed (`.removed` completion).
    var retired: [MotionLayer] = []

    init(base: Presentation) { self.base = base }

    /// The presented value at `now`.
    func value(at now: Double) -> Presentation {
        var v = base
        for layer in layers {
            guard let start = layer.start else { continue }
            v = layer.value(below: v, elapsed: now - start)
        }
        return v
    }
}

/// Transaction frames and deferred completions. A `withAnimation` body is a frame: the graphs whose state it writes (`Graph.noteChange`) are recorded in it,
/// and when the body ends its transaction is queued on those graphs only (`Graph.queued`), so a window never consumes another window's transaction.
/// Completions are drained on the main actor by commit and tick.
@MainActor
enum TransactionContext {
    private final class WeakGraph {
        weak var graph: Graph?
        init(_ graph: Graph) { self.graph = graph }
    }
    private final class Frame {
        var graphs: [ObjectIdentifier] = []
        var touched: [Graph] = []
        init() {}
    }
    /// Every live graph (one per window). `withAnimation` has no graph argument, so the boundary cannot know which graph owns the state the
    /// body will write; each graph settles only its own pending changes, so every live graph is told and none is mistaken for another.
    private static var graphs: [WeakGraph] = []
    private static var frames: [Frame] = []
    /// Transactions whose body wrote no graph's state: the next commit of any graph takes them (they only settle their completion).
    private static var unattached: [AnimationTransaction] = []
    static var deferred: [() -> Void] = []
    static var hasOpenFrame: Bool { !frames.isEmpty }

    static func register(_ graph: Graph) { graphs.append(WeakGraph(graph)) }

    /// A new transaction begins: the changes each graph made before it are settled first (see `Graph.settleAtTransactionBoundary`), so they
    /// are not coalesced with the new transaction's changes. Its body is then a frame, closed by `end`.
    static func begin() {
        graphs.removeAll { $0.graph == nil }
        // Only the outermost transaction an onChange action opens commits the triggering pass: a transaction nested in an open frame belongs to the
        // frame's writes, whose transaction is queued when the frame ends, so committing here would commit them before it is queued.
        let outermost = frames.isEmpty
        for entry in graphs {
            entry.graph?.settleAtTransactionBoundary()
            if outermost { entry.graph?.commitTriggerBeforeTransaction() }
        }
        frames.append(Frame())
    }

    /// The body ended: its transaction is queued on each graph it wrote (or left unattached when it wrote none).
    static func end(_ transaction: AnimationTransaction) {
        guard let frame = frames.popLast() else { return }
        if frame.touched.isEmpty { unattached.append(transaction); return }
        for graph in frame.touched { graph.enqueue(transaction) }
    }

    /// `graph` is written inside the open frames. True when it is the first write to it in the innermost frame.
    @discardableResult
    static func touch(_ graph: Graph) -> Bool {
        var first = false
        for (index, frame) in frames.enumerated() {
            let id = ObjectIdentifier(graph)
            if !frame.graphs.contains(id) {
                frame.graphs.append(id)
                frame.touched.append(graph)
                if index == frames.count - 1 { first = true }
            }
        }
        return first
    }

    static func takeUnattached() -> [AnimationTransaction] {
        let out = unattached
        unattached = []
        return out
    }

    static var unattachedTransactions: [AnimationTransaction] { unattached }

    /// Runs completions in order. A completion may schedule more, so this loops until empty.
    static func drainDeferred() {
        while !deferred.isEmpty {
            let batch = deferred
            deferred = []
            for completion in batch { completion() }
        }
    }
}

/// Runs `body` as an animated transaction. Changes it causes animate at the next commit. The optional
/// `completion` runs once, after the animation has finished or been superseded (SwiftUI shape:
/// `withAnimation(a) { ... } completion: { ... }`).
@MainActor
public func withAnimation<Result>(
    _ animation: Animation? = .default,
    _ body: () throws -> Result,
    completion: (() -> Void)? = nil
) rethrows -> Result {
    let transaction = AnimationTransaction(animation: animation, completion: completion)
    defer { TransactionContext.end(transaction) }
    TransactionContext.begin()
    return try body()
}

/// As `withAnimation`, with the criteria that decide when the completion runs.
@MainActor
public func withAnimation<Result>(
    _ animation: Animation? = .default,
    completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
    _ body: () throws -> Result,
    completion: @escaping () -> Void
) rethrows -> Result {
    let transaction = AnimationTransaction(animation: animation, completion: completion, criteria: completionCriteria)
    defer { TransactionContext.end(transaction) }
    TransactionContext.begin()
    return try body()
}

/// Runs `body` with `transaction`: its animation applies to the changes `body` causes, and `disablesAnimations` makes
/// `.animation(_:value:)` modifiers yield to it (measured: an explicit animation still runs; with none, the modifiers do not).
@MainActor
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    let queued = AnimationTransaction(animation: transaction.animation, completion: nil, disablesAnimations: transaction.disablesAnimations)
    defer { TransactionContext.end(queued) }
    TransactionContext.begin()
    return try body()
}

// MARK: - Engine

extension Graph {
    /// Sets each node's target opacity from its own `.opacity` modifiers and its parent's target.
    func assignOpacity(_ node: Node, parent: Double) {
        var own = 1.0
        if case .modifier(.opacity(let value)) = node.kind { own = value }
        node.targetOpacity = parent * own
        for child in childNodes(node) { assignOpacity(child, parent: node.targetOpacity) }
    }

    /// Applies the flush's transactions to the nodes whose targets changed.
    func applyTransactions(_ transactions: [AnimationTransaction], changed: [Node]) {
        let firstPresentation = self.sequence == 0
        // Nodes presented for the first time start from their transition's initial state (a snap or a layer then brings them to their target).
        let fresh = Set(changed.filter { !$0.committed }.map { ObjectIdentifier($0) })
        for node in changed where !node.committed {
            node.committed = true
            if firstPresentation {
                node.presentedFrame = node.frame
                node.presentedOpacity = node.targetOpacity
            } else {
                let initial = insertionStart(node, fresh: fresh)
                node.presentedFrame = initial.frame
                node.presentedOpacity = initial.opacity
            }
        }
        if firstPresentation || transactions.isEmpty {
            for node in changed { snap(node) }
            return
        }
        let explicit = transactions.filter { $0.scope == nil }
        let scoped = transactions.filter { $0.scope != nil }
        let disables = explicit.contains { $0.disablesAnimations }
        var byScope: [ObjectIdentifier: AnimationTransaction] = [:]
        if !disables { for t in scoped { byScope[ObjectIdentifier(t.scope!)] = t } }
        // Every queued transaction finishes at its commit unless it started a layer.
        defer { for t in transactions { t.settleIfDone() } }
        // Within one flush the last explicit transaction decides; the earlier ones have nothing left to animate.
        let decisive = explicit.last
        for node in changed {
            var chosen: AnimationTransaction?
            var found = false
            if !byScope.isEmpty {
                var cursor: Node? = node
                while let current = cursor {
                    if let t = byScope[ObjectIdentifier(current)] { chosen = t; found = true; break }
                    cursor = current.parent
                }
            }
            if !found { chosen = decisive }
            guard let transaction = chosen, let animation = transaction.animation,
                  !node.environment.accessibilityReduceMotion else {
                snap(node)
                continue
            }
            startLayer(node, transaction, animation)
        }
    }

    private func startLayer(_ node: Node, _ transaction: AnimationTransaction, _ animation: Animation) {
        guard animation.duration > 0 else {
            snap(node)
            return
        }
        let target = Presentation(frame: node.frame, opacity: node.targetOpacity)
        let chain = node.motion ?? MotionChain(base: Presentation(frame: node.presentedFrame, opacity: node.presentedOpacity))
        let layer = MotionLayer(to: target, animation: animation, transaction: transaction)
        if layer.isSpring {
            let from = (chain.layers.isEmpty ? chain.base : (clock.map { chain.value(at: $0) } ?? chain.layers.last!.to)).components
            layer.springSettle = SpringModel.settle(displacement: zip(target.components, from).map { $0 - $1 }, scale: Double(scale))
        }
        if layer.isSpring, let top = chain.layers.last, top.isSpring, let now = clock, top.start != nil {
            // A spring that interrupts a spring continues from the presented position and velocity (SwiftUI merges them).
            let current = chain.value(at: now)
            let h = 1e-4
            let before = chain.value(at: now - h)
            let c = current.components, b = before.components, t = target.components
            layer.continuation = (
                displacement: (0..<5).map { t[$0] - c[$0] },
                velocity: (0..<5).map { -(c[$0] - b[$0]) / h }
            )
            finishChain(chain)
            chain.base = current
        }
        chain.layers.append(layer)
        node.motion = chain
        if !node.isAnimating {
            node.isAnimating = true
            animating.append(node)
            animatingNeedsSort = true
        }
    }

    /// Ends every layer of the chain at once (a merged spring replaces them): their transactions count as finished.
    func finishChain(_ chain: MotionChain) {
        for layer in chain.layers + chain.retired { endLayer(layer, removal: true) }
        chain.layers = []
        chain.retired = []
    }

    func endLayer(_ layer: MotionLayer, removal: Bool) {
        if !layer.logicallyEnded {
            layer.logicallyEnded = true
            layer.transaction.layerLogicallyEnded()
        }
        if removal {
            layer.finished = true
            layer.transaction.layerRemoved()
        }
    }

    /// Presents the target at once and ends any motion (its transactions count as finished).
    func snap(_ node: Node) {
        if let chain = node.motion {
            node.motion = nil
            finishChain(chain)
        }
        node.presentedFrame = node.frame
        node.presentedOpacity = node.targetOpacity
    }

    /// Ends a node's motion when the node goes away.
    func endMotion(_ node: Node) {
        if let chain = node.motion {
            node.motion = nil
            finishChain(chain)
        }
    }

    /// Interpolates every running motion to `now`. A layer that reaches its end presents its target and finishes. `anchoring` is true only for a
    /// display tick: a layer that has not begun takes `now` as its progress 0 there. A commit (`anchoring` false) leaves such a layer as it is.
    func advanceMotions(now: Double, anchoring: Bool) {
        advanceGhosts(now: now, anchoring: anchoring)
        guard !animating.isEmpty else { return }
        // Only nodes that hold a motion are visited, in path order so completion order does not depend on hashing.
        if animatingNeedsSort {
            animating.sort { $0.idString < $1.idString }
            animatingNeedsSort = false
        }
        defer {
            animating.removeAll { node in
                guard node.motion == nil || !node.alive else { return false }
                node.isAnimating = false
                return true
            }
        }
        for node in animating {
            guard let chain = node.motion else { continue }
            let value = advanceChain(chain, now: now, anchoring: anchoring)
            if chain.layers.isEmpty {
                node.motion = nil
                node.presentedFrame = chain.base.frame
                node.presentedOpacity = chain.base.opacity
            } else {
                node.presentedFrame = value.frame
                node.presentedOpacity = value.opacity
            }
        }
    }

    /// Moves one chain to `now`: anchors unstarted layers on a display tick, fires logical completions, folds finished layers into the base and,
    /// when none is left, fires the removal completions. Returns the presented value (the chain's base once it has no layer).
    func advanceChain(_ chain: MotionChain, now: Double, anchoring: Bool) -> Presentation {
        func inclusiveEnd(_ layer: MotionLayer) -> Bool { layer.inclusiveEnd }
        if anchoring {
            for layer in chain.layers where layer.start == nil { layer.start = now }
        }
        for layer in chain.layers {
            guard let start = layer.start else { continue }
            let elapsed = now - start
            if !layer.logicallyEnded, elapsed >= layer.animation.duration {
                layer.logicallyEnded = true
                layer.transaction.layerLogicallyEnded()
            }
            if inclusiveEnd(layer) ? elapsed >= layer.visualDuration : elapsed > layer.visualDuration { layer.finished = true }
        }
        let value = chain.value(at: now)
        // finished layers at the bottom of the chain fold into its base
        while let first = chain.layers.first, first.finished {
            chain.base = first.to
            chain.layers.removeFirst()
            chain.retired.append(first)
        }
        if chain.layers.isEmpty {
            let retired = chain.retired
            chain.retired = []
            for layer in retired { endLayer(layer, removal: true) }
        }
        return value
    }
}
