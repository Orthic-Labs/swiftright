import Foundation
import Observation
import SwiftRightRuntime

// Port of probes/sr0-o/fixtures Common/RowModel.swift, EventLog.swift, FakeEngine.swift for F1.
// Animation, F2-F9 and the window-close path are not ported (F1 only).

struct Row: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
}

/// Records events as dictionaries and echoes each as one `EVT {json}` line on stdout.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String: Any]] = []

    func emit(_ kind: String, node: String, payload: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        let event: [String: Any] = ["seq": recorded.count, "kind": kind, "node_id": node, "payload": payload]
        recorded.append(event)
        if let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            print("EVT " + line)
        }
    }

    func events() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func count(kind: String? = nil, node: String? = nil, phase: String? = nil) -> Int {
        events().filter { event in
            if let kind, event["kind"] as? String != kind { return false }
            if let node, event["node_id"] as? String != node { return false }
            if let phase, (event["payload"] as? [String: Any])?["phase"] as? String != phase { return false }
            return true
        }.count
    }
}

/// Injected fake engine. Each operation suspends until the driver releases its key.
/// Cancellation is observed but never resumes the operation (same rule as the Mac fixture).
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
}

/// Shared F1 model. Structural and text changes go through one path each; every committed effect
/// passes the commit gate (the same rule as RowModel.commitAllowed on the Mac).
@MainActor
@Observable
final class RowModel {
    @ObservationIgnored let fixtureNumber = 1
    @ObservationIgnored let log: EventLog
    @ObservationIgnored let engine: FakeEngine
    /// Set by the bridge backend; called after every model mutation so the backend flushes the runtime.
    @ObservationIgnored var onMutate: (() -> Void)?
    /// Focus handle from the screen's @FocusState. Registered while the screen body evaluates.
    @ObservationIgnored var focusBinding: FocusState<UUID?>.Binding?
    /// Per-row text write path, registered by each row's body (same route as the TextField binding).
    @ObservationIgnored var textInputHandlers: [UUID: (String) -> Void] = [:]
    @ObservationIgnored var screenGeneration = 0
    @ObservationIgnored var rejectedEffects = 0

    var rows: [Row]
    var insertRequests = 0

    init(log: EventLog, engine: FakeEngine) {
        self.log = log
        self.engine = engine
        rows = (1...10).map { slot in
            Row(id: Self.rowID(fixture: 1, slot: slot), text: "Row \(slot)")
        }
    }

    /// Deterministic row identity, as in the Mac fixture.
    nonisolated static func rowID(fixture: Int, slot: Int) -> UUID {
        let first = String(0xF000_0000 + fixture, radix: 16, uppercase: true)
        let tail = String(slot)
        let last = String(repeating: "0", count: 12 - tail.count) + tail
        return UUID(uuidString: "\(first)-0000-4000-8000-\(last)")!
    }

    func rowID(_ slot: Int) -> UUID { Self.rowID(fixture: fixtureNumber, slot: slot) }

    /// The slot a row was created with, from its identity (stable across inserts). Used for AX labels.
    nonisolated static func slot(of id: UUID) -> Int {
        Int(id.uuidString.suffix(12)) ?? 0
    }

    func row(_ id: UUID) -> Row? { rows.first { $0.id == id } }

    func index(of id: UUID) -> Int? { rows.firstIndex { $0.id == id } }

    func registerFocus(_ binding: FocusState<UUID?>.Binding) {
        focusBinding = binding
    }

    func registerTextInput(_ id: UUID, _ handler: @escaping (String) -> Void) {
        textInputHandlers[id] = handler
    }

    /// Text write for one row: user input and AX SetValue both come here.
    func editText(_ id: UUID, _ newValue: String) {
        if let handler = textInputHandlers[id] {
            handler(newValue)
        } else {
            setText(id, newValue)
        }
        onMutate?()
    }

    func setText(_ id: UUID, _ text: String) {
        guard let index = index(of: id) else { return }
        rows[index].text = text
    }

    func insertRow(_ row: Row, at index: Int, tag: String) {
        let position = min(max(index, 0), rows.count)
        rows.insert(row, at: position)
        log.emit("state", node: "model", payload: [
            "op": "insert", "index": position, "id": row.id.uuidString, "tag": tag,
        ])
        onMutate?()
    }

    /// The Insert above button. Starts the guarded engine insert (key "insert-above"); the
    /// self-test releases that key, as the Mac self-test's `release` step does.
    func requestInsertAboveFromButton() {
        insertRequests += 1
        log.emit("state", node: "toolbar/insert", payload: ["op": "invoke", "seq": insertRequests])
        Task { @MainActor in
            await self.runInsertAbove(key: "insert-above", slot: 99)
        }
    }

    // MARK: Guarded effects

    private func commitAllowed(_ effect: String, owner: String, ownerGeneration: Int, cancelled: Bool) -> Bool {
        let reason: String?
        if cancelled {
            reason = "task-cancelled"
        } else if ownerGeneration != screenGeneration {
            reason = "stale-owner-generation"
        } else {
            reason = nil
        }
        if let reason {
            rejectedEffects += 1
            log.emit("effect", node: owner, payload: ["phase": "rejected", "effect": effect, "reason": reason, "gen": ownerGeneration])
            return false
        }
        log.emit("effect", node: owner, payload: ["phase": "commit", "effect": effect, "gen": ownerGeneration])
        return true
    }

    private func runEffect(_ effect: String, key: String, owner: String) async -> Int? {
        let gen = screenGeneration
        let log = self.log
        let engine = self.engine
        log.emit("lifecycle", node: owner, payload: ["phase": "task-start", "effect": effect, "key": key, "gen": gen])
        defer {
            log.emit("effect", node: owner, payload: ["phase": "cleanup", "effect": effect, "gen": gen])
        }
        let value = await withTaskCancellationHandler {
            await engine.call(key, owner: owner)
        } onCancel: {
            log.emit("lifecycle", node: owner, payload: ["phase": "task-cancel", "effect": effect, "key": key])
        }
        guard commitAllowed(effect, owner: owner, ownerGeneration: gen, cancelled: Task.isCancelled) else {
            return nil
        }
        return value
    }

    func runInsertAbove(key: String, slot: Int) async {
        guard let value = await runEffect("insert-above", key: key, owner: "screen") else { return }
        insertRow(Row(id: rowID(slot), text: "Engine \(value)"), at: 0, tag: key)
    }
}
