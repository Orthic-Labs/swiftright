import Foundation

/// Thread-safe JSONL sink. Called from MainActor code, from Layout (nonisolated) and from
/// cancellation handlers, so it is lock-protected rather than actor-isolated.
/// Event fields: fixture, step, kind (state|lifecycle|effect|focus|selection), node_id, payload, mono_ns.
public final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private let fixture: String
    private var step = "init"
    private var sink: FileHandle?
    private var recorded: [[String: Any]] = []
    private var lastSignature: [String: String] = [:]

    init(fixture: String, path: String?) {
        self.fixture = fixture
        if let path {
            FileManager.default.createFile(atPath: path, contents: nil)
            sink = FileHandle(forWritingAtPath: path)
        }
    }

    var count: Int { lock.withLock { recorded.count } }

    func events() -> [[String: Any]] { lock.withLock { recorded } }

    func setStep(_ name: String) { lock.withLock { step = name } }

    func emit(_ kind: String, node: String, payload: [String: Any] = [:]) {
        lock.withLock {
            let event: [String: Any] = [
                "fixture": fixture,
                "step": step,
                "kind": kind,
                "node_id": node,
                "payload": payload,
                "mono_ns": DispatchTime.now().uptimeNanoseconds,
            ]
            recorded.append(event)
            if let sink, let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) {
                try? sink.write(contentsOf: data)
                try? sink.write(contentsOf: Data([0x0A]))
            }
        }
    }

    /// Emits only when the signature differs from the previous one recorded for the same node.
    /// Used for layout placements, whose call count is SwiftUI-internal and not part of the contract.
    func emitIfChanged(_ kind: String, node: String, signature: String, payload: [String: Any]) {
        let changed = lock.withLock { () -> Bool in
            if lastSignature[node] == signature { return false }
            lastSignature[node] = signature
            return true
        }
        if changed { emit(kind, node: node, payload: payload) }
    }
}
