import Foundation

/// Tells a screen reader's focus on a button apart from the focus request that arrives in front of a UI Automation Invoke.
///
/// Evidence (SR0, F8 on the Dell): all 46 UIA `Invoke` calls on buttons in the recordings read reached the host as an AX
/// `focus` action on the same node and then an AX `invoke`, 0.59 to 3.84 ms apart: 6 in
/// `probes/sr0-o/f1-cross/cross-evidence/F8/win-events-w{1,2,3}.txt` (native C recorder) and 40 in
/// `probes/sr0-s/fresh-on-bridge/out/matrix-final/F8-none-r*.txt` (.NET driver). Neither client calls `SetFocus`, and
/// AccessKit's own `Invoke` sends `Action::Click` only (accesskit_windows 0.35.1 `node.rs`: `Invoke` -> `click`; `Action::Focus`
/// occurs once, in `SetFocus`). The focus request therefore comes from the platform between the client and the provider. A screen
/// reader's own `SetFocus` (Narrator moving to a button) is assumed not to be followed within milliseconds by an invoke of that
/// node, since it navigates first and activates later; that assumption is not yet recorded (Narrator run owed).
///
/// macOS `AXPress` leaves the keyboard focus and the VoiceOver focus where they were, so an activation alone must not move
/// the focus. The gate holds a button focus request for `settleNS`: an invoke of the same node inside that window cancels
/// it, anything else lets it stand (the host applies it when `expired` or `confirm` returns the node).
///
/// Pure value logic with caller-supplied monotonic nanoseconds, so it is testable without a window.
public struct ButtonFocusGate: Equatable {
    /// How long a button focus request waits for an invoke of the same node. The largest observed gap is 3.84 ms; this is 15x
    /// that and shorter than four display frames, so a screen reader's own focus move is delayed by at most this long.
    public static let settleNS: UInt64 = 60_000_000

    private var pendingNode: NodeID?
    private var pendingSince: UInt64 = 0

    public init() {}

    /// The node whose focus request is being held, if any.
    public var pending: NodeID? { pendingNode }

    /// Holds a focus request on `node`. Returns the earlier held request when it was for a different node: that one is now
    /// confirmed and the caller applies it. A repeated request for the same node only restarts the window.
    public mutating func request(_ node: NodeID, at now: UInt64) -> NodeID? {
        let earlier = pendingNode
        pendingNode = node
        pendingSince = now
        return earlier == node ? nil : earlier
    }

    /// An invoke of `node` arrived. True when it cancelled a held focus request on the same node (the request was the
    /// platform's preamble to the invoke); the caller then logs and drops it. False leaves the held request alone, for
    /// `confirm` (a request that already outlived the window is the screen reader's own).
    public mutating func cancelForInvoke(of node: NodeID, at now: UInt64) -> Bool {
        guard pendingNode == node, now &- pendingSince <= Self.settleNS else { return false }
        pendingNode = nil
        return true
    }

    /// Takes the held request whatever its age (another input arrived, so the request stood on its own).
    public mutating func confirm() -> NodeID? {
        defer { pendingNode = nil }
        return pendingNode
    }

    /// Takes the held request when it has waited out the window.
    public mutating func expired(at now: UInt64) -> NodeID? {
        guard let node = pendingNode, now &- pendingSince > Self.settleNS else { return nil }
        pendingNode = nil
        return node
    }

    /// Age of the held request in nanoseconds, nil when none (diagnostics).
    public func age(at now: UInt64) -> UInt64? {
        pendingNode == nil ? nil : now &- pendingSince
    }
}
