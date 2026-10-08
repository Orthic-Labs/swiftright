import Foundation
import Observation
#if os(macOS)
import SwiftUI
#endif

struct Row: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
}

/// Owner identity for guarded effects. Generation is read from the owner, never from the view.
enum EffectOwner {
    case screen
    case control(String)
    case row(UUID)
}

/// Shared fixture model. Structural changes are logged here; text edits are logged by the row view.
/// Every committed effect passes through `commitAllowed`, which is the only commit gate.
@MainActor
@Observable
final class RowModel {
    let fixtureNumber: Int
    let log: EventLog
    let engine: FakeEngine
    private let reducedVariant: Bool

    var rows: [Row]
    var screenGeneration = 0
    var rowGeneration: [UUID: Int] = [:]
    var closed = false
    var animationEnabled: Bool
    var focusRequest: UUID?
    var focusRequestSeq = 0
    var insertRequestSeq = 0
    var committedNotes: [UUID: Int] = [:]
    var screenNote: Int?

    init(fixtureNumber: Int, log: EventLog, engine: FakeEngine, reducedMotion: Bool) {
        self.fixtureNumber = fixtureNumber
        self.log = log
        self.engine = engine
        self.reducedVariant = reducedMotion
        self.animationEnabled = !reducedMotion
        self.rows = (1...10).map { slot in
            Row(id: Self.rowID(fixture: fixtureNumber, slot: slot), text: "Row \(slot)")
        }
    }

    /// Deterministic row identity: fixture number in the first group, slot in the last group.
    nonisolated static func rowID(fixture: Int, slot: Int) -> UUID {
        let first = String(0xF000_0000 + fixture, radix: 16, uppercase: true)
        let tail = String(slot)
        let last = String(repeating: "0", count: 12 - tail.count) + tail
        return UUID(uuidString: "\(first)-0000-4000-8000-\(last)")!
    }

    func rowID(_ slot: Int) -> UUID { Self.rowID(fixture: fixtureNumber, slot: slot) }

    func index(of id: UUID) -> Int? { rows.firstIndex { $0.id == id } }

    func generation(of owner: EffectOwner) -> Int {
        switch owner {
        case .screen, .control: return screenGeneration
        case .row(let id): return rowGeneration[id, default: 0]
        }
    }

    func ownerNode(_ owner: EffectOwner) -> String {
        switch owner {
        case .screen: return "screen"
        case .control(let name): return name
        case .row(let id): return id.uuidString
        }
    }

    func snapshot(_ reason: String) {
        log.emit("state", node: "model", payload: [
            "reason": reason,
            "count": rows.count,
            "rows": rows.map { ["id": $0.id.uuidString, "text": $0.text] as [String: String] },
            "closed": closed,
        ])
    }

    // MARK: Structural mutations

    func insertRow(_ row: Row, at index: Int, animated: Bool = false, tag: String = "") {
        let position = min(max(index, 0), rows.count)
        if animated && animationEnabled {
            let log = self.log
            log.emit("lifecycle", node: "animation", payload: ["phase": "start", "tag": tag])
            withAnimation(.linear(duration: 0.6), completionCriteria: .logicallyComplete) {
                rows.insert(row, at: position)
            } completion: {
                log.emit("lifecycle", node: "animation", payload: ["phase": "complete", "tag": tag])
            }
        } else {
            rows.insert(row, at: position)
        }
        log.emit("state", node: "model", payload: [
            "op": "insert", "index": position, "id": row.id.uuidString, "tag": tag, "animated": animated && animationEnabled,
        ])
    }

    func removeRow(_ id: UUID) {
        guard let index = index(of: id) else { return }
        rows.remove(at: index)
        rowGeneration[id, default: 0] += 1
        log.emit("state", node: id.uuidString, payload: ["op": "remove", "index": index, "owner_gen": generation(of: .row(id))])
    }

    func moveRow(from offsets: IndexSet, to destination: Int) {
        rows.move(fromOffsets: offsets, toOffset: destination)
        log.emit("state", node: "model", payload: [
            "op": "move", "from": Array(offsets), "to": destination, "ids": rows.map { $0.id.uuidString },
        ])
    }

    func setText(_ id: UUID, _ text: String) {
        guard let index = index(of: id) else { return }
        rows[index].text = text
    }

    func requestFocus(_ id: UUID) {
        focusRequest = id
        focusRequestSeq += 1
    }

    func requestInsert() {
        insertRequestSeq += 1
    }

    /// Both burst inserts in one turn (kept for the original step). Their in-animation interleaving is SwiftUI timing.
    func burstInsert() {
        burstInsertOne(0)
        burstInsertOne(1)
    }

    /// One animated insert: 0 = A (slot 200), 1 = B (slot 201). The driver settles between them.
    func burstInsertOne(_ which: Int) {
        if which == 0 {
            insertRow(Row(id: rowID(200), text: "Anim A"), at: 0, animated: true, tag: "A")
        } else {
            insertRow(Row(id: rowID(201), text: "Anim B"), at: 0, animated: true, tag: "B")
        }
    }

    func setReducedMotion(_ systemReduce: Bool) {
        let enabled = !(systemReduce || reducedVariant)
        if enabled != animationEnabled {
            animationEnabled = enabled
        }
        log.emit("lifecycle", node: "animation", payload: ["phase": "policy", "enabled": enabled, "system_reduce": systemReduce, "variant_reduce": reducedVariant])
    }

    func markClosed() {
        guard !closed else { return }
        closed = true
        screenGeneration += 1
        log.emit("lifecycle", node: "window", payload: ["phase": "root-disappear"])
    }

    // MARK: Guarded effects

    /// The single commit gate. Called on the MainActor immediately before any commit.
    private func commitAllowed(_ effect: String, owner: EffectOwner, ownerGeneration: Int, cancelled: Bool) -> Bool {
        let node = ownerNode(owner)
        let reason: String?
        if closed {
            reason = "window-closed"
        } else if cancelled {
            reason = "task-cancelled"
        } else if ownerGeneration != generation(of: owner) {
            reason = "stale-owner-generation"
        } else {
            reason = nil
        }
        if let reason {
            log.emit("effect", node: node, payload: ["phase": "rejected", "effect": effect, "reason": reason, "gen": ownerGeneration])
            return false
        }
        log.emit("effect", node: node, payload: ["phase": "commit", "effect": effect, "gen": ownerGeneration])
        return true
    }

    /// Suspends on the fake engine. Returns the value only if the commit gate passes.
    private func runEffect(_ effect: String, key: String, owner: EffectOwner) async -> Int? {
        let node = ownerNode(owner)
        let gen = generation(of: owner)
        let log = self.log
        let engine = self.engine
        log.emit("lifecycle", node: node, payload: ["phase": "task-start", "effect": effect, "key": key, "gen": gen])
        defer {
            log.emit("effect", node: node, payload: ["phase": "cleanup", "effect": effect, "gen": gen])
        }
        let value = await withTaskCancellationHandler {
            await engine.call(key, owner: node)
        } onCancel: {
            log.emit("lifecycle", node: node, payload: ["phase": "task-cancel", "effect": effect, "key": key])
        }
        guard commitAllowed(effect, owner: owner, ownerGeneration: gen, cancelled: Task.isCancelled) else {
            return nil
        }
        return value
    }

    func runToolbarInsert() async {
        let seq = insertRequestSeq
        guard seq > 0 else { return }
        guard let value = await runEffect("insert-above", key: "insert-toolbar-\(seq)", owner: .control("toolbar/insert")) else {
            return
        }
        insertRow(Row(id: rowID(100 + seq), text: "Toolbar \(value)"), at: 0, tag: "toolbar-\(seq)")
    }

    func runInsertAbove(key: String, slot: Int) async {
        guard let value = await runEffect("insert-above", key: key, owner: .screen) else { return }
        insertRow(Row(id: rowID(slot), text: "Engine \(value)"), at: 0, tag: key)
    }

    func runRowUpdate(key: String, slot: Int) async {
        guard let value = await runEffect("row-update", key: key, owner: .row(rowID(slot))) else { return }
        setText(rowID(slot), "Row \(slot) updated \(value)")
    }

    func runRowLoad(_ id: UUID) async {
        let gen = generation(of: .row(id))
        guard let value = await runEffect("row-load", key: "load-\(id.uuidString)-g\(gen)", owner: .row(id)) else {
            return
        }
        committedNotes[id] = value
        log.emit("state", node: id.uuidString, payload: ["op": "note", "value": value])
    }

    func runScreenSync() async {
        let gen = screenGeneration
        guard let value = await runEffect("screen-sync", key: "screen-sync-g\(gen)", owner: .screen) else { return }
        screenNote = value
    }
}
