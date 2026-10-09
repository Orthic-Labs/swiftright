import Foundation

// SR0-OVERRIDE O5 (new API, CONTRACT F4): owner-generation guard for results of `.task` work.
// Stock SCUI has no liveness check (assessment B3): a `Binding` keeps its storage alive, so a late
// write from a cancelled or removed row's task still lands. `TaskOwner.current` is the owner of the
// running `.task`; `commit(_:)` runs the closure only while that owner is still mounted.
#if !SCUI_STOCK_TASKGUARD
@MainActor
public final class TaskOwner {
    @TaskLocal public static var current: TaskOwner?

    public private(set) var isAlive = true

    public init() {}

    /// Called when the task restarts (id change) or its node unmounts.
    public func invalidate() { isAlive = false }

    /// Runs `commit` only if the owning `.task` node is still mounted and this is its latest run.
    @discardableResult
    public func commit(_ commit: () -> Void) -> Bool {
        guard isAlive else { return false }
        commit()
        return true
    }
}
#endif
