import Foundation

/// Keeps `BridgeWindow.metrics()` consistent with the window-metrics events the host has already been given.
///
/// Contract: the payload of a `.windowMetrics` event (`i0` = width px, `i1` = height px, `x` = scale) is authoritative.
/// From the moment the bridge delivers such an event for the live window, `metrics()` returns that size and scale, not the
/// renderer getter's (`swr_window_get_metrics`) value, which it consulted only for `active` and as the answer before any
/// event. SR0 findings section 12: at ready the getter read 800x1396 while the client was 800x600, and the host still read
/// 800x1396 after the event carrying 800x600.
///
/// Pure value logic, so it is testable without the DLL.
public struct MetricsLatch: Equatable {
    public private(set) var width: UInt32?
    public private(set) var height: UInt32?
    public private(set) var scale: Float?

    public init() {}

    /// Records a window-metrics event payload. Negative sizes clamp to 0; a non-positive or non-finite scale is ignored
    /// (the previous scale, if any, stays). Returns false for any event that is not a window-metrics event.
    @discardableResult
    public mutating func apply(_ ev: BridgeEvent) -> Bool {
        guard ev.kind == .windowMetrics else { return false }
        width = UInt32(max(ev.i0, 0))
        height = UInt32(max(ev.i1, 0))
        if ev.x.isFinite, ev.x > 0 { scale = ev.x }
        return true
    }

    /// The metrics to report: the event's size and scale once one was seen, else the getter's. `active` is not part of the
    /// event, so it always comes from the getter.
    public func resolve(getter: (width: UInt32, height: UInt32, scale: Float, active: Bool))
        -> (width: UInt32, height: UInt32, scale: Float, active: Bool)
    {
        guard let w = width, let h = height else { return getter }
        return (w, h, scale ?? getter.scale, getter.active)
    }
}
