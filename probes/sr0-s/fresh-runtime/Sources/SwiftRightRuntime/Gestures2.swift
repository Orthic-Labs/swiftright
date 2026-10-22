import Foundation

// Issue #84 (SR2 S3/S5): TapGesture, SpatialTapGesture, DragGesture with onChanged / onEnded, and `.gesture`, `.simultaneousGesture`, `.highPriorityGesture`.
//
// The host reports the pointer in logical points: `pointerPressed(atX:y:)`, `pointerDragged(toX:y:)` while the button is down, and `pointerReleased(atX:y:)`. On a press the
// gesture modifiers whose view holds the point (and that are enabled and take hits) form the active set: every high-priority gesture, the deepest plain `.gesture` (a child's
// gesture hides its ancestors' plain gestures), and every simultaneous gesture. Moves and the release go to the active set until the release. A modifier's view is hit by the
// frame of the view it modifies (as `.onTapGesture`).
//   - TapGesture(count:): fires `onEnded` when the press is released inside the view without having moved 10 points or more; `count` consecutive such taps within 0.5 s
//     (a single tap reports at once).
//   - SpatialTapGesture(count:): the same with the release location in `coordinateSpace`.
//   - DragGesture(minimumDistance:coordinateSpace:): `onChanged` from the first move that is `minimumDistance` (10) points from the press, then on every move; `onEnded` on release
//     (only when the drag began). `velocity` is points per second over the last move; `predictedEnd*` extrapolates it 0.25 s.
// Not modelled: custom Gestures, `updating`/`GestureState`, `sequenced`/`simultaneously`/`exclusively`, `LongPressGesture`, pressure, multi-touch, pointer capture outside the view
// (a drag continues wherever the pointer goes).

/// Apple: https://developer.apple.com/documentation/swiftui/gesturemask
public struct GestureMask: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let none = GestureMask([])
    public static let gesture = GestureMask(rawValue: 1)
    public static let subviews = GestureMask(rawValue: 2)
    public static let all: GestureMask = [.gesture, .subviews]
}

/// What the graph drives for one gesture modifier.
public class GestureRecognizer {
    init() {}
    func pressed(local: CGPoint, global: CGPoint, time: TimeInterval) {}
    func moved(local: CGPoint, global: CGPoint, time: TimeInterval) {}
    func released(local: CGPoint, global: CGPoint, time: TimeInterval, inside: Bool) {}
}

/// Apple: https://developer.apple.com/documentation/swiftui/gesture
public protocol Gesture {
    associatedtype Value
    func makeRecognizer() -> GestureRecognizer
}

final class GestureHook {
    enum Mode { case exclusive, simultaneous, high }
    let mode: Mode
    let mask: GestureMask
    let make: () -> GestureRecognizer
    init(mode: Mode, mask: GestureMask, make: @escaping () -> GestureRecognizer) { self.mode = mode; self.mask = mask; self.make = make }
}

private let tapSlop: CGFloat = 10

private func inSpace(_ space: CoordinateSpace, local: CGPoint, global: CGPoint) -> CGPoint { space == .local ? local : global }

/// Apple: https://developer.apple.com/documentation/swiftui/tapgesture
public struct TapGesture: Gesture {
    public typealias Value = ()
    public var count: Int
    var ended: (() -> Void)?
    public init(count: Int = 1) { self.count = count }
    public func onEnded(_ action: @escaping (()) -> Void) -> TapGesture { var g = self; g.ended = { action(()) }; return g }
    public func makeRecognizer() -> GestureRecognizer { TapRecognizer(count: count, fire: { _ in ended?() }, space: .local) }
}

/// Apple: https://developer.apple.com/documentation/swiftui/spatialtapgesture
public struct SpatialTapGesture: Gesture {
    public struct Value: Equatable, Sendable { public var location: CGPoint }
    public var count: Int
    public var coordinateSpace: CoordinateSpace
    var ended: ((Value) -> Void)?
    public init(count: Int = 1, coordinateSpace: CoordinateSpace = .local) { self.count = count; self.coordinateSpace = coordinateSpace }
    public func onEnded(_ action: @escaping (Value) -> Void) -> SpatialTapGesture { var g = self; g.ended = action; return g }
    public func makeRecognizer() -> GestureRecognizer { TapRecognizer(count: count, fire: { ended?(Value(location: $0)) }, space: coordinateSpace) }
}

final class TapRecognizer: GestureRecognizer {
    let count: Int, fire: (CGPoint) -> Void, space: CoordinateSpace
    private var start: CGPoint?, travelled: CGFloat = 0, taps = 0, lastTap: TimeInterval = -.infinity
    init(count: Int, fire: @escaping (CGPoint) -> Void, space: CoordinateSpace) { self.count = max(1, count); self.fire = fire; self.space = space }
    override func pressed(local: CGPoint, global: CGPoint, time: TimeInterval) { start = global; travelled = 0 }
    override func moved(local: CGPoint, global: CGPoint, time: TimeInterval) {
        guard let start else { return }
        travelled = max(travelled, hypot(global.x - start.x, global.y - start.y))
    }
    override func released(local: CGPoint, global: CGPoint, time: TimeInterval, inside: Bool) {
        defer { start = nil }
        guard start != nil, inside, travelled < tapSlop else { taps = 0; return }
        taps = time - lastTap <= 0.5 ? taps + 1 : 1
        lastTap = time
        if taps >= count { taps = 0; fire(inSpace(space, local: local, global: global)) }
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/draggesture
public struct DragGesture: Gesture {
    /// Apple: https://developer.apple.com/documentation/swiftui/draggesture/value
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var translation: CGSize { CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y) }
        public var velocity: CGSize
        public var predictedEndLocation: CGPoint { CGPoint(x: location.x + velocity.width * 0.25, y: location.y + velocity.height * 0.25) }
        public var predictedEndTranslation: CGSize { CGSize(width: translation.width + velocity.width * 0.25, height: translation.height + velocity.height * 0.25) }
    }
    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace
    var changed: ((Value) -> Void)?
    var ended: ((Value) -> Void)?
    public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) { self.minimumDistance = minimumDistance; self.coordinateSpace = coordinateSpace }
    public func onChanged(_ action: @escaping (Value) -> Void) -> DragGesture { var g = self; g.changed = action; return g }
    public func onEnded(_ action: @escaping (Value) -> Void) -> DragGesture { var g = self; g.ended = action; return g }
    public func makeRecognizer() -> GestureRecognizer { DragRecognizer(gesture: self) }
}

final class DragRecognizer: GestureRecognizer {
    let gesture: DragGesture
    private var startGlobal: CGPoint?, startInSpace = CGPoint.zero, began = false
    private var last: (point: CGPoint, time: TimeInterval)?, velocity = CGSize.zero
    init(gesture: DragGesture) { self.gesture = gesture }

    override func pressed(local: CGPoint, global: CGPoint, time: TimeInterval) {
        startGlobal = global; startInSpace = inSpace(gesture.coordinateSpace, local: local, global: global); began = false; last = (global, time); velocity = .zero
    }
    private func value(_ local: CGPoint, _ global: CGPoint, _ time: TimeInterval) -> DragGesture.Value {
        DragGesture.Value(time: Date(timeIntervalSinceReferenceDate: time), location: inSpace(gesture.coordinateSpace, local: local, global: global), startLocation: startInSpace, velocity: velocity)
    }
    private func track(_ global: CGPoint, _ time: TimeInterval) {
        if let last, time > last.time { velocity = CGSize(width: (global.x - last.point.x) / (time - last.time), height: (global.y - last.point.y) / (time - last.time)) }
        last = (global, time)
    }
    override func moved(local: CGPoint, global: CGPoint, time: TimeInterval) {
        guard let startGlobal else { return }
        track(global, time)
        if !began {
            guard hypot(global.x - startGlobal.x, global.y - startGlobal.y) >= gesture.minimumDistance else { return }
            began = true
        }
        gesture.changed?(value(local, global, time))
    }
    override func released(local: CGPoint, global: CGPoint, time: TimeInterval, inside: Bool) {
        defer { startGlobal = nil; began = false }
        guard startGlobal != nil, began else { return }
        track(global, time)
        gesture.ended?(value(local, global, time))
    }
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/gesture(_:including:)
    public func gesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
        Modified(content: self, spec: .gesture(GestureHook(mode: .exclusive, mask: mask, make: { gesture.makeRecognizer() })))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/simultaneousgesture(_:including:)
    public func simultaneousGesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
        Modified(content: self, spec: .gesture(GestureHook(mode: .simultaneous, mask: mask, make: { gesture.makeRecognizer() })))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/highprioritygesture(_:including:)
    public func highPriorityGesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
        Modified(content: self, spec: .gesture(GestureHook(mode: .high, mask: mask, make: { gesture.makeRecognizer() })))
    }
}

extension Graph {
    private func gestureModifierNodes() -> [(node: Node, depth: Int)] {
        var out: [(Node, Int)] = []
        func walk(_ n: Node, _ depth: Int) {
            guard n.alive else { return }
            if case .modifier(.gesture) = n.kind { out.append((n, depth)) }
            for c in childNodes(n) { walk(c, depth + 1) }
        }
        if let root { walk(root, 0) }
        return out
    }

    private func gestureFrame(_ n: Node) -> LayoutRect {
        var f = n.frame
        var c = n
        while childNodes(c).count == 1, let child = childNodes(c).first {
            switch child.kind {
            case .modifier(.offset(let dx, let dy)): f = LayoutRect(x: f.minX + dx, y: f.minY + dy, width: f.width, height: f.height)
            case .modifier(.tap), .modifier(.hover), .modifier(.gesture): break
            default: return f
            }
            c = child
        }
        return f
    }

    private func gestureTime() -> TimeInterval { clock ?? Date().timeIntervalSinceReferenceDate }

    private func local(_ n: Node, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let f = gestureFrame(n)
        return CGPoint(x: x - f.minX, y: y - f.minY)
    }

    /// The pointer button went down at (x, y) logical points. Returns whether any gesture took the press.
    @discardableResult
    public func pointerPressed(atX x: CGFloat, y: CGFloat) -> Bool {
        let hit = gestureModifierNodes().filter { entry in
            let f = gestureFrame(entry.node)
            return x >= f.minX && x < f.maxX && y >= f.minY && y < f.maxY && entry.node.environment.isEnabled && entry.node.environment.allowsHitTesting
        }
        func hook(_ n: Node) -> GestureHook? { if case .modifier(.gesture(let h)) = n.kind { return h } else { return nil } }
        var active: [Node] = hit.filter { hook($0.node)?.mode == .high }.map(\.node)
        if let deepest = hit.filter({ hook($0.node)?.mode == .exclusive }).max(by: { $0.depth < $1.depth }) { active.append(deepest.node) }
        active += hit.filter { hook($0.node)?.mode == .simultaneous }.map(\.node)
        gestureActive = active
        let now = gestureTime()
        for n in active {
            if n.gestureRecognizer == nil, let h = hook(n) { n.gestureRecognizer = h.make() }
            n.gestureRecognizer?.pressed(local: local(n, x, y), global: CGPoint(x: x, y: y), time: now)
        }
        flush()
        return !active.isEmpty
    }

    /// The pointer moved to (x, y) with the button down.
    public func pointerDragged(toX x: CGFloat, y: CGFloat) {
        let now = gestureTime()
        for n in gestureActive where n.alive { n.gestureRecognizer?.moved(local: local(n, x, y), global: CGPoint(x: x, y: y), time: now) }
        flush()
    }

    /// The pointer button went up at (x, y).
    public func pointerReleased(atX x: CGFloat, y: CGFloat) {
        let now = gestureTime()
        let active = gestureActive
        gestureActive = []
        for n in active where n.alive {
            let f = gestureFrame(n)
            let inside = x >= f.minX && x < f.maxX && y >= f.minY && y < f.maxY
            n.gestureRecognizer?.released(local: local(n, x, y), global: CGPoint(x: x, y: y), time: now, inside: inside)
        }
        flush()
    }
}
