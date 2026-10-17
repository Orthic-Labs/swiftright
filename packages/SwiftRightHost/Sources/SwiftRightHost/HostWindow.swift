import Foundation
import SwiftRightBridge
import SwiftRightRuntime

/// The window a host opens (decision H17). The public window/app entry of SwiftRightHost: one value carries everything the
/// renderer needs at run time, and `Bridge.run(_:)` passes it through unchanged.
public struct HostWindowOptions: Equatable {
    public var title: String
    /// Initial client size in DIPs (device-independent pixels at 96 dpi).
    public var width: UInt32
    public var height: UInt32
    /// Ask for hover and drag pointer events (needs a 0.9 renderer; ignored below that).
    public var pointerMoves: Bool
    /// An explicit render scale: a device scale factor used instead of the window's DPI, for fixed-scale exports and the same
    /// rendering on every display (2.5 is 240 dpi). The client area is `width * renderScale` by `height * renderScale` physical
    /// pixels, text is measured and rasterised at it, and the window's metrics report it. nil keeps the window's DPI. Needs a 0.10
    /// renderer: a renderer without it makes `run` throw, never ignore. If the window moves to a display with a different DPI the
    /// scale stays `renderScale`; the window's physical size follows the OS and the host re-measures on the metrics event.
    public var renderScale: Float?
    /// Ask for pointer wheel events (`BridgeEvent.wheel`, issue #31). Off by default: a host that does not ask leaves WM_MOUSEWHEEL to
    /// the window as before. Needs a 0.11 renderer (`Bridge.supportsPointerWheel`); on an older one the request is dropped, never guessed.
    public var pointerWheel: Bool

    public init(title: String, width: UInt32, height: UInt32, pointerMoves: Bool = false, renderScale: Float? = nil, pointerWheel: Bool = false) {
        self.title = title
        self.width = width
        self.height = height
        self.pointerMoves = pointerMoves
        self.renderScale = renderScale
        self.pointerWheel = pointerWheel
    }
}

public extension Bridge {
    /// Opens the window described by `options` and runs the renderer loop (see `Bridge.run(title:width:height:pointerMoves:renderScale:pointerWheel:)`).
    /// The wheel request reaches the renderer only when `supportsPointerWheel` (a 0.10 renderer gets no wheel events).
    @discardableResult
    func run(_ options: HostWindowOptions) throws -> Int32 {
        try HostWindowOptions.forward(options) { title, width, height, pointerMoves, renderScale, pointerWheel in
            try run(title: title, width: width, height: height, pointerMoves: pointerMoves, renderScale: renderScale,
                    pointerWheel: pointerWheel && supportsPointerWheel)
        }
    }
}

extension HostWindowOptions {
    /// The one place the options become `Bridge.run` arguments. A seam for tests: every field is passed through, none is derived.
    static func forward(_ o: HostWindowOptions, _ run: (String, UInt32, UInt32, Bool, Float?, Bool) throws -> Int32) rethrows -> Int32 {
        try run(o.title, o.width, o.height, o.pointerMoves, o.renderScale, o.pointerWheel)
    }
}

/// Wheel and scroll bar input of a window that asked for `pointerWheel` (issue #31). Pure conversions are static; the routing calls the
/// runtime's scroll API and the painter's scroller geometry. The host calls `flush` after any input that returns true, as after other input.
public enum HostScrollInput {
    /// Lines one wheel event scrolls. `deltaY` is in WHEEL_DELTA units with the Windows sign (positive = the wheel moved away from the user,
    /// content scrolls up), so one notch at the default 3 lines is -3 (content moves down for a negative count, up for a positive one).
    /// Precise touchpad deltas give fractional lines. `wheelScrollLines` 0 (the user turned wheel scrolling off) scrolls nothing.
    public static func lines(deltaY: Int32, wheelScrollLines: Int) -> Double {
        -(Double(deltaY) / Double(BridgeEvent.wheelDelta)) * Double(wheelScrollLines)
    }

    /// A physical pixel coordinate as logical points at the window's render scale.
    public static func points(_ pixels: Float, scale: Float) -> Double { Double(pixels) / Double(scale) }

    /// Routes a wheel event to the innermost scroll container under its point. Returns whether the offset changed.
    @MainActor
    public static func wheel(_ w: BridgeEvent.Wheel, graph: Graph, scale: Float, wheelScrollLines: Int) -> Bool {
        let lines = lines(deltaY: w.deltaY, wheelScrollLines: wheelScrollLines)
        guard lines != 0 else { return false }
        return graph.scrollWheel(atX: points(w.x, scale: scale), y: points(w.y, scale: scale), lines: lines)
    }
}

/// The scroll bar pointer of one window: a primary press inside a scroller's strip (`ResolvedNodePainter.scrollerLayouts`) is handed to the
/// runtime, moves while it is down drag the thumb, and the release ends it. Mirrors the slider's press, drag and release.
@MainActor
public final class HostScrollBarPointer {
    /// The runtime id of the scroll container whose scroll bar the primary button holds, until the release.
    public private(set) var dragging: String?

    public init() {}

    /// A primary button down at physical px (x, y). Returns true when the press landed on a scroll bar (the host then flushes).
    /// The strip nearest the point is taken when strips overlap (nested scroll views).
    public func press(x: Float, y: Float, graph: Graph, painter: ResolvedNodePainter) -> Bool {
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let hit = painter.scrollerLayouts
            .filter { ScrollerPainter.cgRect($0.value.strip).contains(point) }
            .min { area($0.value.strip) < area($1.value.strip) }
        guard let id = hit?.key else { return false }
        graph.scrollBarPress(id, atY: HostScrollInput.points(y, scale: painter.scale))
        dragging = id
        return true
    }

    private func area(_ r: Rect) -> CGFloat { let c = ScrollerPainter.cgRect(r); return c.width * c.height }

    /// A pointer move while the primary button is down: drags the thumb to the pointer's root y. Returns false when no thumb is held.
    public func move(y: Float, graph: Graph, painter: ResolvedNodePainter) -> Bool {
        guard let id = dragging else { return false }
        graph.scrollBarDrag(id, toY: HostScrollInput.points(y, scale: painter.scale))
        return true
    }

    /// The primary button up: ends the drag, if one is under way.
    public func release(graph: Graph) {
        guard let id = dragging else { return }
        graph.scrollBarRelease(id)
        dragging = nil
    }
}
