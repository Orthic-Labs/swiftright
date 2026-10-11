import Foundation

// Animation semantics (SR0-S F6 oracle, headless form).
//
// A transaction is created by `withAnimation` or by a changed `.animation(_:value:)`, and is queued.
// The next commit drains the queue and applies the transactions in order to every node whose layout
// target or target opacity changed in that flush:
//   - an animated transaction starts a motion from the node's presented value to the new target. A
//     later motion on the same node supersedes the earlier one (interruption), and the superseded
//     transaction counts as finished;
//   - a nil-animation transaction, a reduce-motion node, or a zero duration snaps to the target;
//   - a newly inserted node fades in (opacity 0 to its target) under an animated transaction.
// Motions advance only through `Graph.tick(now:)` (host clock). A motion begins at the first tick after it
// was created: that tick is its progress 0, whatever the host clock reads (a real display tick carries an
// absolute monotonic time, not a count from zero) and however long ticks were off before. A flush between
// ticks never begins, advances or ends a motion. A transaction's completion runs once, after every motion
// it started has finished or been superseded; a transaction that started none completes at its commit.
// Completions run after the commit record has been delivered.

/// A timing curve over normalized time.
public struct Animation: Sendable, Equatable {
    public enum Curve: Sendable, Equatable {
        case linear
        case easeIn
        case easeOut
        case easeInOut
    }

    /// Tag recorded in commit records.
    public let name: String
    /// Seconds.
    public let duration: Double
    public let curve: Curve

    public init() {
        self.init(name: "default")
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
}

extension Animation.Curve {
    /// Eased progress for normalized time `t` in 0...1.
    func value(at t: Double) -> Double {
        let x = min(max(t, 0), 1)
        switch self {
        case .linear: return x
        case .easeIn: return x * x
        case .easeOut: return 1 - (1 - x) * (1 - x)
        case .easeInOut: return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
        }
    }
}

/// One transaction: its animation (nil = no animation) and an optional completion.
@MainActor
final class AnimationTransaction {
    let animation: Animation?
    private var completion: (() -> Void)?
    /// Motions this transaction started that have not finished or been superseded.
    private(set) var pending = 0
    private var settled = false

    init(animation: Animation?, completion: (() -> Void)?) {
        self.animation = animation
        self.completion = completion
    }

    func motionStarted() {
        pending += 1
    }

    func motionEnded() {
        pending -= 1
        settleIfDone()
    }

    /// Schedules the completion once, when no motion of this transaction is still running.
    func settleIfDone() {
        guard pending == 0, !settled else { return }
        settled = true
        if let completion {
            TransactionContext.deferred.append(completion)
            self.completion = nil
        }
    }
}

/// An in-flight interpolation of one node.
struct Motion {
    let from: LayoutRect
    let to: LayoutRect
    let fromOpacity: Double
    let toOpacity: Double
    /// Host time of progress 0. Nil until the first tick after the motion was created (`advanceMotions` fixes it).
    var start: Double?
    let duration: Double
    let curve: Animation.Curve
    let transaction: AnimationTransaction
}

/// Transaction queue and deferred completions. Both are drained on the main actor by commit and tick.
@MainActor
enum TransactionContext {
    private static var queued: [AnimationTransaction] = []
    static var deferred: [() -> Void] = []
    static var queuedCount: Int { queued.count }

    static func enqueue(_ transaction: AnimationTransaction) {
        queued.append(transaction)
    }

    static func takeQueued() -> [AnimationTransaction] {
        let out = queued
        queued = []
        return out
    }

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
    defer { TransactionContext.enqueue(transaction) }
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

    /// Applies the flush's transactions, in order, to the nodes whose targets changed.
    func applyTransactions(_ transactions: [AnimationTransaction], changed: [Node]) {
        for node in changed where !node.committed {
            // A node presented for the first time starts fully transparent; a snap or a fade-in
            // motion then brings it to its target.
            node.committed = true
            node.presentedFrame = node.frame
            node.presentedOpacity = 0
        }
        if transactions.isEmpty {
            for node in changed { snap(node) }
            return
        }
        for transaction in transactions {
            for node in changed {
                if let animation = transaction.animation, !node.environment.accessibilityReduceMotion {
                    startMotion(node, transaction, animation)
                } else {
                    snap(node)
                }
            }
            transaction.settleIfDone()
        }
    }

    private func startMotion(_ node: Node, _ transaction: AnimationTransaction, _ animation: Animation) {
        guard animation.duration > 0 else {
            snap(node)
            return
        }
        if let superseded = node.motion {
            node.motion = nil
            superseded.transaction.motionEnded()
        }
        node.motion = Motion(
            from: node.presentedFrame,
            to: node.frame,
            fromOpacity: node.presentedOpacity,
            toOpacity: node.targetOpacity,
            start: nil,
            duration: animation.duration,
            curve: animation.curve,
            transaction: transaction
        )
        transaction.motionStarted()
        if !node.isAnimating {
            node.isAnimating = true
            animating.append(node)
            animatingNeedsSort = true
        }
    }

    /// Presents the target at once and ends any motion (its transaction counts as finished).
    func snap(_ node: Node) {
        if let motion = node.motion {
            node.motion = nil
            motion.transaction.motionEnded()
        }
        node.presentedFrame = node.frame
        node.presentedOpacity = node.targetOpacity
    }

    /// Interpolates every running motion to `now`. A motion that reaches its end presents its target
    /// and finishes its transaction. `anchoring` is true only for a display tick: a motion that has not begun
    /// takes `now` as its progress 0 there. A commit (`anchoring` false) leaves such a motion as it is.
    func advanceMotions(now: Double, anchoring: Bool) {
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
            guard var motion = node.motion else { continue }
            if motion.start == nil {
                guard anchoring else { continue }
                motion.start = now
                node.motion = motion
            }
            let progress = (now - (motion.start ?? now)) / motion.duration
            if progress >= 1 {
                node.motion = nil
                node.presentedFrame = motion.to
                node.presentedOpacity = motion.toOpacity
                motion.transaction.motionEnded()
            } else {
                let eased = motion.curve.value(at: max(0, progress))
                node.presentedFrame = interpolate(motion.from, motion.to, eased)
                node.presentedOpacity = motion.fromOpacity + (motion.toOpacity - motion.fromOpacity) * eased
            }
        }
    }

    private func interpolate(_ a: LayoutRect, _ b: LayoutRect, _ t: Double) -> LayoutRect {
        let k = CGFloat(t)
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * k }
        return LayoutRect(
            x: mix(a.minX, b.minX),
            y: mix(a.minY, b.minY),
            width: mix(a.width, b.width),
            height: mix(a.height, b.height)
        )
    }
}
