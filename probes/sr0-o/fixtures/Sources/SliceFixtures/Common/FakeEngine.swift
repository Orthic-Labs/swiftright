import Foundation

/// Injected fake engine. Each operation suspends until the driver releases its key.
/// Cancellation is observed through the caller's onCancel hook but never resumes the operation:
/// a late release still delivers its value, so stale-result rejection is exercised rather than avoided.
@MainActor
final class FakeEngine {
    private struct Pending {
        let key: String
        let owner: String
        let continuation: CheckedContinuation<Int, Never>
    }

    private var pending: [Pending] = []
    private let log: EventLog

    init(log: EventLog) {
        self.log = log
    }

    func call(_ key: String, owner: String) async -> Int {
        log.emit("effect", node: owner, payload: ["phase": "engine-request", "key": key])
        return await withCheckedContinuation { continuation in
            pending.append(Pending(key: key, owner: owner, continuation: continuation))
        }
    }

    @discardableResult
    func release(_ key: String, value: Int) -> Bool {
        guard let index = pending.firstIndex(where: { $0.key == key }) else {
            log.emit("effect", node: "engine", payload: ["phase": "release-no-waiter", "key": key])
            return false
        }
        let entry = pending.remove(at: index)
        log.emit("effect", node: entry.owner, payload: ["phase": "engine-release", "key": key, "value": value])
        entry.continuation.resume(returning: value)
        return true
    }

    var pendingKeys: [String] { pending.map(\.key) }

    /// Releases every waiter in request order with value 0.
    func releaseAll() {
        for key in pendingKeys {
            release(key, value: 0)
        }
    }
}
