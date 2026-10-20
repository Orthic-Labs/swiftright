import Foundation

// SR2 block R2 (issue #37, docs/sr2-plan.md): Animatable shapes.
//
// A shape node's geometry is a third presented channel next to frame and opacity (`Presentation.geometry`). When an animated transaction changes a
// shape's geometry, the node's motion layer interpolates it with the same progress it gives the frame, so layering, interruption, springs and
// completions behave as they do for frames. As in SwiftUI, the presented shape is the NEW shape value with only its `animatableData` replaced by the
// interpolated value: properties outside `animatableData` take their new values at once, and a shape whose data is `EmptyAnimatableData` switches at once.
// Animated per shape: `trim(from:to:)` (from, to), `inset(by:)` (amount), `RoundedRectangle` (corner radius), and a custom shape's `animatableData`.
// Not animated (switch at once, as in SwiftUI): Rectangle, Circle, Capsule, Path. Paint (colour, line width) is not interpolated in this block.

/// Apple: https://developer.apple.com/documentation/swiftui/vectorarithmetic
public protocol VectorArithmetic: AdditiveArithmetic {
    mutating func scale(by rhs: Double)
    var magnitudeSquared: Double { get }
}

extension VectorArithmetic {
    public func scaled(by rhs: Double) -> Self {
        var copy = self
        copy.scale(by: rhs)
        return copy
    }
    /// `self + (other - self) * t`.
    func interpolated(towards other: Self, amount t: Double) -> Self { self + (other - self).scaled(by: t) }
}

extension Double: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= rhs }
    public var magnitudeSquared: Double { self * self }
}

extension Float: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= Float(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}

extension CGFloat: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= CGFloat(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}

/// Apple: https://developer.apple.com/documentation/swiftui/emptyanimatabledata
public struct EmptyAnimatableData: VectorArithmetic, Sendable {
    public init() {}
    public static var zero: EmptyAnimatableData { EmptyAnimatableData() }
    public static func + (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { lhs }
    public static func - (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { lhs }
    public mutating func scale(by rhs: Double) {}
    public var magnitudeSquared: Double { 0 }
}

/// Apple: https://developer.apple.com/documentation/swiftui/animatablepair
public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>: VectorArithmetic {
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public static var zero: AnimatablePair { AnimatablePair(.zero, .zero) }
    public static func + (lhs: AnimatablePair, rhs: AnimatablePair) -> AnimatablePair { AnimatablePair(lhs.first + rhs.first, lhs.second + rhs.second) }
    public static func - (lhs: AnimatablePair, rhs: AnimatablePair) -> AnimatablePair { AnimatablePair(lhs.first - rhs.first, lhs.second - rhs.second) }
    public mutating func scale(by rhs: Double) {
        first.scale(by: rhs)
        second.scale(by: rhs)
    }
    public var magnitudeSquared: Double { first.magnitudeSquared + second.magnitudeSquared }
}

extension AnimatablePair: Sendable where First: Sendable, Second: Sendable {}

/// Apple: https://developer.apple.com/documentation/swiftui/animatable
///
/// The requirement is main-actor isolated so that a user shape (main-actor inferred through `View`) and a nonisolated one both conform; the graph
/// reads and writes it only on the main actor.
public protocol Animatable {
    associatedtype AnimatableData: VectorArithmetic
    @MainActor var animatableData: AnimatableData { get set }
}

extension Animatable where AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }
}

// MARK: - Built-in shapes' animatable data (as SwiftUI declares them)

extension TrimmedShape {
    nonisolated public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(startFraction, endFraction) }
        set { startFraction = newValue.first; endFraction = newValue.second }
    }
}

// MARK: - Geometry interpolation

extension ShapeGeometry {
    /// The geometry presented `t` of the way from `from` to `to` (t may leave 0...1 under a bouncing spring): the target's structure with its
    /// animatable values interpolated. A structure that changed, or a part with no animatable data, takes the target at once.
    static func interpolate(_ from: ShapeGeometry?, _ to: ShapeGeometry?, _ t: Double) -> ShapeGeometry? {
        guard let from, let to else { return to }
        let k = CGFloat(t)
        switch (from, to) {
        case (.roundedRectangle(let a, _), .roundedRectangle(let b, let style)):
            return .roundedRectangle(cornerRadius: max(0, a + (b - a) * k), style: style)
        case (.trimmed(let baseA, let fromA, let toA), .trimmed(let baseB, let fromB, let toB)):
            return .trimmed(interpolate(baseA, baseB, t) ?? baseB, from: fromA + (fromB - fromA) * k, to: toA + (toB - toA) * k)
        case (.inset(let baseA, let a), .inset(let baseB, let b)):
            return .inset(interpolate(baseA, baseB, t) ?? baseB, by: a + (b - a) * k)
        case (.custom(let a), .custom(let b)):
            return .custom(b.interpolated(from: a, amount: t) ?? b)
        default:
            return to
        }
    }
}
