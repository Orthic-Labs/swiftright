import Foundation

// Issue #84 (SR2 S4): keyframeAnimator, KeyframeTrack and the Linear / Move / Cubic / Spring keyframes, Spring and UnitCurve.
//
// `keyframeAnimator(initialValue:repeating:content:keyframes:)` evaluates its tracks at the time since the animation started on the host clock (`Graph.tick(now:)`): the
// start is the first evaluation, and with `trigger:` a change of the trigger restarts it. Each track drives one property of the value from its initial value through its
// keyframes in order; the animation ends at the longest track (and holds the final values) or loops with `repeating: true`.
//   - LinearKeyframe: linear (or eased by `timingCurve`) from the previous value to `to` over `duration`. MoveKeyframe: jumps to `to` at once.
//   - CubicKeyframe: a cubic Hermite from the previous value to `to`, with the given start and end velocities (zero when nil).
//   - SpringKeyframe: a damped spring from the previous value (and velocity) toward `to`; the spring's `duration` and `bounce` give ω = 2π / duration and damping ratio 1 - bounce
//     (bounce 0 critical, above 0 oscillating), the keyframe lasting `duration` seconds (default: the spring's own duration). NOT measured against SwiftUI's SpringKeyframe.
// Property values are `VectorArithmetic` (Double, CGFloat, Float). Not modelled: Animatable structs with several components as one property, `KeyframeTimeline`, and
// `keyframeAnimator` pausing off screen.

/// Apple: https://developer.apple.com/documentation/swiftui/unitcurve
public struct UnitCurve: Sendable {
    let c1x: Double, c1y: Double, c2x: Double, c2y: Double
    public static let linear = UnitCurve(c1x: 0, c1y: 0, c2x: 1, c2y: 1)
    public static let easeIn = UnitCurve(c1x: 0.42, c1y: 0, c2x: 1, c2y: 1)
    public static let easeOut = UnitCurve(c1x: 0, c1y: 0, c2x: 0.58, c2y: 1)
    public static let easeInOut = UnitCurve(c1x: 0.42, c1y: 0, c2x: 0.58, c2y: 1)
    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
        UnitCurve(c1x: Double(startControlPoint.x), c1y: Double(startControlPoint.y), c2x: Double(endControlPoint.x), c2y: Double(endControlPoint.y))
    }
    public func value(at t: Double) -> Double { UnitBezier(c1x, c1y, c2x, c2y).value(at: t) }
}

/// Apple: https://developer.apple.com/documentation/swiftui/spring
public struct Spring: Sendable, Equatable {
    public var duration: Double
    public var bounce: Double
    public init(duration: Double = 0.5, bounce: Double = 0) { self.duration = duration; self.bounce = bounce }
    public static let smooth = Spring(duration: 0.5, bounce: 0)
    public static let snappy = Spring(duration: 0.5, bounce: 0.15)
    public static let bouncy = Spring(duration: 0.5, bounce: 0.3)
    public static func smooth(duration: Double = 0.5, extraBounce: Double = 0) -> Spring { Spring(duration: duration, bounce: extraBounce) }
    public static func snappy(duration: Double = 0.5, extraBounce: Double = 0) -> Spring { Spring(duration: duration, bounce: 0.15 + extraBounce) }
    public static func bouncy(duration: Double = 0.5, extraBounce: Double = 0) -> Spring { Spring(duration: duration, bounce: 0.3 + extraBounce) }

    /// Position and velocity at `t` of a unit-mass spring released from displacement `x0` (from the target) with velocity `v0`.
    func state(x0: Double, v0: Double, t: Double) -> (x: Double, v: Double) {
        let omega = 2 * Double.pi / max(duration, 1e-6)
        let zeta = min(max(1 - bounce, 0.0001), 1)
        if zeta >= 0.9999 {
            let e = exp(-omega * t), c = v0 + omega * x0
            return ((x0 + c * t) * e, (v0 - omega * c * t) * e)
        }
        let wd = omega * (1 - zeta * zeta).squareRoot()
        let e = exp(-zeta * omega * t), a = x0, b = (v0 + zeta * omega * x0) / wd
        let cs = cos(wd * t), sn = sin(wd * t)
        let x = e * (a * cs + b * sn)
        let v = e * ((-zeta * omega) * (a * cs + b * sn) + wd * (-a * sn + b * cs))
        return (x, v)
    }
}

/// One keyframe of a track, evaluated from the previous end state.
public struct KeyframeSegment<Value: VectorArithmetic> {
    let duration: Double
    /// (value, velocity) at `t` seconds into the segment, from `start` with `velocity`.
    let evaluate: (_ start: Value, _ velocity: Value, _ t: Double) -> (Value, Value)
}

/// Apple: https://developer.apple.com/documentation/swiftui/linearkeyframe
public struct LinearKeyframe<Value: VectorArithmetic> {
    let segment: KeyframeSegment<Value>
    public init(_ to: Value, duration: TimeInterval, timingCurve: UnitCurve = .linear) {
        segment = KeyframeSegment(duration: duration) { start, _, t in
            let p = duration > 0 ? timingCurve.value(at: min(max(t / duration, 0), 1)) : 1
            return (start + (to - start).scaled(by: p), (to - start).scaled(by: duration > 0 ? 1 / duration : 0))
        }
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/movekeyframe
public struct MoveKeyframe<Value: VectorArithmetic> {
    let segment: KeyframeSegment<Value>
    public init(_ to: Value) { segment = KeyframeSegment(duration: 0) { _, _, _ in (to, .zero) } }
}

/// Apple: https://developer.apple.com/documentation/swiftui/cubickeyframe
public struct CubicKeyframe<Value: VectorArithmetic> {
    let segment: KeyframeSegment<Value>
    public init(_ to: Value, duration: TimeInterval, startVelocity: Value? = nil, endVelocity: Value? = nil) {
        segment = KeyframeSegment(duration: duration) { start, v0, t in
            guard duration > 0 else { return (to, .zero) }
            let u = min(max(t / duration, 0), 1)
            let m0 = (startVelocity ?? .zero).scaled(by: duration), m1 = (endVelocity ?? .zero).scaled(by: duration)
            let h00 = 2 * u * u * u - 3 * u * u + 1, h10 = u * u * u - 2 * u * u + u, h01 = -2 * u * u * u + 3 * u * u, h11 = u * u * u - u * u
            let value = start.scaled(by: h00) + m0.scaled(by: h10) + to.scaled(by: h01) + m1.scaled(by: h11)
            let d00 = 6 * u * u - 6 * u, d10 = 3 * u * u - 4 * u + 1, d01 = -6 * u * u + 6 * u, d11 = 3 * u * u - 2 * u
            let velocity = (start.scaled(by: d00) + m0.scaled(by: d10) + to.scaled(by: d01) + m1.scaled(by: d11)).scaled(by: 1 / duration)
            return (value, velocity)
        }
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/springkeyframe
public struct SpringKeyframe<Value: VectorArithmetic> {
    let segment: KeyframeSegment<Value>
    public init(_ to: Value, duration: TimeInterval? = nil, spring: Spring = Spring(), startVelocity: Value? = nil) {
        let length = duration ?? spring.duration
        segment = KeyframeSegment(duration: length) { start, velocity, t in
            // the spring acts on the displacement of the start from the target, with the given start velocity (or the one carried from the previous keyframe)
            let v0 = startVelocity ?? velocity
            let d = start - to
            // vector values spring component-wise through the scalar solution applied to the displacement's scale
            let mag = d.magnitudeSquared.squareRoot()
            guard mag > 0 else { return (to, .zero) }
            let unit = d.scaled(by: 1 / mag)
            let vAlong = ((v0 + unit).magnitudeSquared - v0.magnitudeSquared - unit.magnitudeSquared) / 2   // the velocity's component along the displacement
            let s = spring.state(x0: mag, v0: vAlong, t: t)
            return (to + unit.scaled(by: s.x), unit.scaled(by: s.v))
        }
    }
}

@resultBuilder
public enum KeyframeTrackContentBuilder<Value: VectorArithmetic> {
    public static func buildExpression(_ k: LinearKeyframe<Value>) -> KeyframeSegment<Value> { k.segment }
    public static func buildExpression(_ k: MoveKeyframe<Value>) -> KeyframeSegment<Value> { k.segment }
    public static func buildExpression(_ k: CubicKeyframe<Value>) -> KeyframeSegment<Value> { k.segment }
    public static func buildExpression(_ k: SpringKeyframe<Value>) -> KeyframeSegment<Value> { k.segment }
    public static func buildBlock(_ segments: KeyframeSegment<Value>...) -> [KeyframeSegment<Value>] { segments }
}

/// A track of one property: its duration and its effect on the value at a time.
public struct KeyframeTrackBox<Root> {
    let duration: Double
    let apply: (inout Root, Double) -> Void
}

/// Apple: https://developer.apple.com/documentation/swiftui/keyframetrack
public struct KeyframeTrack<Root, Value: VectorArithmetic> {
    let box: KeyframeTrackBox<Root>
    public init(_ keyPath: WritableKeyPath<Root, Value>, @KeyframeTrackContentBuilder<Value> content: () -> [KeyframeSegment<Value>]) {
        let segments = content()
        let total = segments.reduce(0) { $0 + $1.duration }
        box = KeyframeTrackBox(duration: total) { root, time in
            var start = root[keyPath: keyPath], velocity = Value.zero, elapsed = 0.0
            for segment in segments {
                if time < elapsed + segment.duration || segment.duration == 0 && time <= elapsed {
                    root[keyPath: keyPath] = segment.evaluate(start, velocity, time - elapsed).0
                    return
                }
                let end = segment.evaluate(start, velocity, segment.duration)
                (start, velocity) = (end.0, end.1)
                elapsed += segment.duration
            }
            root[keyPath: keyPath] = start
        }
    }
}

@resultBuilder
public enum KeyframesBuilder<Root> {
    public static func buildExpression<Value: VectorArithmetic>(_ track: KeyframeTrack<Root, Value>) -> KeyframeTrackBox<Root> { track.box }
    public static func buildBlock(_ tracks: KeyframeTrackBox<Root>...) -> [KeyframeTrackBox<Root>] { tracks }
}

/// The animator's start time and trigger, kept with its node across evaluations (the graph looks for members that are dynamic properties).
@MainActor
struct KeyframeBinder: DynamicPropertyStorage {
    final class Box { var token: AnyHashable?; var start: Double? }
    final class Cell { var box = Box() }
    let cell = Cell()
    var box: Box { cell.box }
    func bindDynamicProperty(to node: Node, key: String) {
        if let existing = node.storage[key] as? Box { cell.box = existing } else { node.storage[key] = cell.box }
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/keyframeanimator
public struct KeyframeAnimator<Value, Content: View>: View {
    let initialValue: Value
    let repeating: Bool
    let trigger: AnyHashable?
    let content: (Value) -> Content
    let tracks: [KeyframeTrackBox<Value>]
    let binder = KeyframeBinder()
    let clock = ClockBinder()

    @MainActor public var body: some View {
        // before the first host tick the animation is at its start; the start time is the first tick (or the tick after a change of the trigger)
        let ticked = clock.source?.ticked ?? false
        let now = clock.source?.now ?? 0
        if binder.box.token != trigger { binder.box.start = nil; binder.box.token = trigger }
        if ticked, binder.box.start == nil { binder.box.start = now }
        let total = tracks.map(\.duration).max() ?? 0
        var t = ticked ? max(0, now - (binder.box.start ?? now)) : 0
        if repeating, total > 0 { t = t.truncatingRemainder(dividingBy: total) }
        var value = initialValue
        for track in tracks { track.apply(&value, t) }
        return content(value)
    }
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/keyframeanimator(initialvalue:repeating:content:keyframes:)
    @MainActor public func keyframeAnimator<Value, V: View>(initialValue: Value, repeating: Bool = true, @ViewBuilder content: @escaping (PlaceholderContentView, Value) -> V,
                                                          @KeyframesBuilder<Value> keyframes: @escaping (Value) -> [KeyframeTrackBox<Value>]) -> some View {
        KeyframeAnimator(initialValue: initialValue, repeating: repeating, trigger: nil, content: { value in content(PlaceholderContentView(view: AnyView(self)), value) }, tracks: keyframes(initialValue))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/keyframeanimator(initialvalue:trigger:content:keyframes:)
    @MainActor public func keyframeAnimator<Value, Trigger: Equatable, V: View>(initialValue: Value, trigger: Trigger, @ViewBuilder content: @escaping (PlaceholderContentView, Value) -> V,
                                                                              @KeyframesBuilder<Value> keyframes: @escaping (Value) -> [KeyframeTrackBox<Value>]) -> some View {
        KeyframeAnimator(initialValue: initialValue, repeating: false, trigger: AnyHashable(HashableEquatable(trigger)), content: { value in content(PlaceholderContentView(view: AnyView(self)), value) }, tracks: keyframes(initialValue))
    }
}

/// What `keyframeAnimator`'s content closure receives: the modified view.
public struct PlaceholderContentView: View {
    let view: AnyView
    @MainActor public var body: some View { view }
}

private struct HashableEquatable<T: Equatable>: Hashable {
    let value: T
    init(_ value: T) { self.value = value }
    static func == (a: Self, b: Self) -> Bool { a.value == b.value }
    func hash(into hasher: inout Hasher) { hasher.combine(0) }
}
