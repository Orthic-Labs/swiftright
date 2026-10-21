import Foundation
import SwiftRightRuntime

/// The pressed state of Buttons for one window (issue #60 pass 3): a primary press on an enabled Button highlights it, the highlight follows the pointer out of and back into its frame
/// (AppKit tracks an NSButton the same way), and a release inside runs its action. The window's pointer events (physical px) go through `press`, `move` and `release`; a host that
/// already taps a Button on press (the capture hosts, the fresh-on-bridge backend) switches to this: `press` returns the id it highlighted, `release` returns the id to tap.
@MainActor
public final class HostButtonPointer {
    /// The runtime id of the Button the primary button went down on, until the release.
    public private(set) var held: String?

    public init() {}

    /// A primary button down at physical px (x, y). Highlights the enabled Button under the point and returns its id; nil when none is there (nothing is held).
    @discardableResult
    public func press(x: Float, y: Float, scale: Float, graph: Graph) -> String? {
        guard let id = graph.buttonID(atX: CGFloat(HostScrollInput.points(x, scale: scale)), y: CGFloat(HostScrollInput.points(y, scale: scale))), graph.setPressedButton(id) else { return nil }
        held = id
        graph.flush()
        return id
    }

    /// A pointer move while the primary button is down: the held Button is highlighted while the pointer is inside it. Returns true when the highlight changed.
    @discardableResult
    public func move(x: Float, y: Float, scale: Float, graph: Graph) -> Bool {
        guard let id = held else { return false }
        let inside = graph.buttonID(atX: CGFloat(HostScrollInput.points(x, scale: scale)), y: CGFloat(HostScrollInput.points(y, scale: scale))) == id
        guard inside != (graph.pressedButton == id) else { return false }
        graph.setPressedButton(inside ? id : nil)
        graph.flush()
        return true
    }

    /// The primary button up: clears the highlight and returns the id of the Button to tap, which is the held one when the pointer is still inside it (nil when it left, or none was held).
    @discardableResult
    public func release(x: Float, y: Float, scale: Float, graph: Graph) -> String? {
        guard let id = held else { return nil }
        held = nil
        let inside = graph.buttonID(atX: CGFloat(HostScrollInput.points(x, scale: scale)), y: CGFloat(HostScrollInput.points(y, scale: scale))) == id
        graph.setPressedButton(nil)
        graph.flush()
        return inside ? id : nil
    }
}
