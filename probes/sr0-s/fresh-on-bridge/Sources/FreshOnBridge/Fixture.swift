import Foundation
import Observation
import SwiftRightRuntime

// Port of probes/sr0-o/fixtures Common/RowModel.swift, EventLog.swift, FakeEngine.swift for F1-F9.
// Differences from the Mac fixture are listed in RESULT.md (runtime gaps, host-side window close).

struct Row: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
}

enum FixtureKind: String, CaseIterable, Sendable {
    case F1, F2, F3, F4, F5, F6, F7, F8, F9

    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}

enum F3Container: String, Sendable {
    case list, vstack, lazy
}

/// Per-run selection, parsed from the command line (see main.swift).
struct FixtureOptions: Sendable {
    var fixture: FixtureKind = .F1
    var reducedVariant = false
    var f3Container: F3Container = .list
    var f3GapMs = 0
    var f9NoTasks = false
    /// Test or app override of the runtime reduce-motion environment (`--reduce-motion-override on|off`). Nil = the default
    /// (animations on): the Windows "Animation effects" setting is read and logged but never decides (RESULT.md 2026-10-10).
    var reduceMotionOverride: Bool? = nil
    /// Label printed on the SELFTEST line, e.g. `F3 list-1s`.
    var label: String = "F1"
    /// `--ready-file <path>`: the exe writes this file when its script reaches the close step (awaiting the driver's
    /// WM_CLOSE). drive-fixture.ps1 waits for it before closing, so the window never closes mid-settle.
    var readyFile: String? = nil
    /// `--release-event <name>`: Windows named event the in-process release hook waits on (see Hooks.swift).
    var releaseEvent: String? = nil
    /// `--release-file <path>`: trigger file for the release hook, polled on the display tick, deleted when seen.
    var releaseFile: String? = nil
    /// `--f7-live`: F7 without the programmatic composition. The script waits for the release hook (fired by the
    /// driver in the middle of a real IME composition), which performs the insert-above engine release.
    var f7Live = false
}

/// Records events as dictionaries and echoes each as one `EVT {json}` line on stdout.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String: Any]] = []
    private var lastSignature: [String: String] = [:]

    func emit(_ kind: String, node: String, payload: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        let event: [String: Any] = [
            "seq": recorded.count, "kind": kind, "node_id": node, "payload": payload,
            "mono_ns": DispatchTime.now().uptimeNanoseconds,
        ]
        recorded.append(event)
        if let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            print("EVT " + line)
            // The Windows CRT treats line buffering as full buffering: flush per line so drivers read live.
            fflush(stdout)
        }
    }

    /// Emits only when the signature changes for the node (layout placements; call count is not contract).
    func emitIfChanged(_ kind: String, node: String, signature: String, payload: [String: Any]) {
        let changed = lock.withLock { () -> Bool in
            if lastSignature[node] == signature { return false }
            lastSignature[node] = signature
            return true
        }
        if changed { emit(kind, node: node, payload: payload) }
    }

    func events() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

/// Injected fake engine. Each operation suspends until the self-test releases its key.
/// Cancellation is observed but never resumes the operation (late results are delivered).
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

    func releaseAll() {
        for key in pendingKeys { release(key, value: 0) }
    }

    var pendingKeys: [String] { pending.map(\.key) }
}

/// Owner identity for guarded effects. Generation is read from the owner, never from the view.
enum EffectOwner {
    case screen
    case control(String)
    case row(UUID)
}

/// Shared fixture model. Structural changes are logged here; text edits go through `editText`.
/// Every committed effect passes through `commitAllowed`, the only commit gate.
@MainActor
@Observable
final class RowModel {
    @ObservationIgnored let fixtureNumber: Int
    @ObservationIgnored let log: EventLog
    @ObservationIgnored let engine: FakeEngine
    @ObservationIgnored let reducedVariant: Bool
    /// Set by the bridge backend; called after each model mutation so the backend flushes the runtime.
    @ObservationIgnored var onMutate: (() -> Void)?
    /// Focus handle from the screen's @FocusState, registered while the screen body evaluates.
    @ObservationIgnored var focusBinding: FocusState<UUID?>.Binding?
    /// Per-row text write path, registered by each row's body (same route as the TextField binding).
    @ObservationIgnored var textInputHandlers: [UUID: (String) -> Void] = [:]
    @ObservationIgnored var rowGeneration: [UUID: Int] = [:]
    /// Windows reduce-motion inputs, set by the backend before the graph exists (logged by applyMotionPolicy).
    @ObservationIgnored var systemReduceMotion: Bool?
    @ObservationIgnored var effectiveReduceMotion = false
    @ObservationIgnored var reduceMotionSource = "unset"

    var rows: [Row]
    var screenGeneration = 0
    var closed = false
    var animationEnabled: Bool
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

    /// The slot a row was created with, from its identity. Used for AX labels ("Row N").
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

    // MARK: Focus

    /// Focus change from any source (AX focus, pointer). Logged the way the Mac onChange(focus) logs it.
    func setFocus(_ id: UUID?, source: String) {
        focusBinding?.wrappedValue = id
        logFocus(id, source: source)
    }

    /// Logs a focus the runtime already holds (the initial focus: the runtime set it, the host only reports it).
    func logFocus(_ id: UUID?, source: String) {
        log.emit("focus", node: "focus", payload: ["focused": id?.uuidString ?? "none", "source": source])
    }

    // MARK: Text

    /// Text write for one row: keystrokes (text store) and AX SetValue both come here.
    func editText(_ id: UUID, _ newValue: String) {
        if let handler = textInputHandlers[id] {
            handler(newValue)
        } else {
            guard let index = index(of: id) else { return }
            rows[index].text = newValue
        }
        onMutate?()
    }

    // MARK: Structural mutations

    func insertRow(_ row: Row, at index: Int, animated: Bool = false, tag: String = "") {
        let position = min(max(index, 0), rows.count)
        let animate = animated && animationEnabled
        if animate {
            // The transaction opens here; its completion runs once the motion has finished or been superseded.
            log.emit("lifecycle", node: "animation", payload: ["phase": "start", "tag": tag])
            let log = self.log
            withAnimation(.default, {
                rows.insert(row, at: position)
            }, completion: {
                log.emit("lifecycle", node: "animation", payload: ["phase": "complete", "tag": tag])
            })
        } else {
            rows.insert(row, at: position)
        }
        log.emit("state", node: "model", payload: [
            "op": "insert", "index": position, "id": row.id.uuidString, "tag": tag, "animated": animate,
        ])
        onMutate?()
    }

    func removeRow(_ id: UUID) {
        guard let index = index(of: id) else { return }
        rows.remove(at: index)
        rowGeneration[id, default: 0] += 1
        log.emit("state", node: id.uuidString, payload: [
            "op": "remove", "index": index, "owner_gen": generation(of: .row(id)),
        ])
        onMutate?()
    }

    /// SwiftUI semantics for one offset: `destination` is an insertion index in the original array.
    func moveRow(from offsets: IndexSet, to destination: Int) {
        guard let source = offsets.first, offsets.count == 1, rows.indices.contains(source) else { return }
        let item = rows.remove(at: source)
        let target = destination > source ? destination - 1 : destination
        rows.insert(item, at: min(max(target, 0), rows.count))
        log.emit("state", node: "model", payload: [
            "op": "move", "from": [source], "to": destination, "ids": rows.map { $0.id.uuidString },
        ])
        onMutate?()
    }

    /// Toolbar request: bumps the request id. F8 starts the effect from `.task(id:)` on that id.
    @discardableResult
    func bumpInsertRequest() -> Int {
        insertRequestSeq += 1
        log.emit("input", node: "toolbar/insert", payload: ["op": "invoke", "seq": insertRequestSeq])
        return insertRequestSeq
    }

    /// Toolbar request whose button action starts its own effect (F1-F7 chrome).
    func requestInsert() {
        let seq = bumpInsertRequest()
        Task { @MainActor in
            await self.runToolbarInsert(seq: seq)
        }
    }

    func burstInsert() {
        insertRow(Row(id: rowID(200), text: "Anim A"), at: 0, animated: true, tag: "A")
        insertRow(Row(id: rowID(201), text: "Anim B"), at: 0, animated: true, tag: "B")
    }

    /// Animation policy: the reduced-motion variant flag disables animation transactions (Mac oracle policy).
    /// The override and the variant also reach the runtime environment (snapping; see BridgeBackend). The OS value is logged
    /// as `system_reduce` and does not decide.
    func applyMotionPolicy() {
        let enabled = !reducedVariant
        animationEnabled = enabled
        log.emit("lifecycle", node: "animation", payload: [
            "phase": "policy", "enabled": enabled, "variant_reduce": reducedVariant,
            "system_reduce": systemReduceMotion.map { $0 ? "on" : "off" } ?? "unavailable",
            "effective_reduce": effectiveReduceMotion, "reduce_source": reduceMotionSource,
        ])
    }

    /// Host close: drops the model's references into the view tree (focus binding and per-row text handlers).
    /// Returns the number of references dropped.
    func releaseViewReferences() -> Int {
        let dropped = textInputHandlers.count + (focusBinding == nil ? 0 : 1)
        textInputHandlers = [:]
        focusBinding = nil
        return dropped
    }

    /// Host-side window close (the runtime has no root-disappear). Mirrors the Mac root onDisappear.
    func markClosed() {
        guard !closed else { return }
        closed = true
        screenGeneration += 1
        log.emit("lifecycle", node: "window", payload: ["phase": "root-disappear", "source": "host-window-close"])
    }

    // MARK: Guarded effects

    private func commitAllowed(_ effect: String, owner: EffectOwner, gen: Int, cancelled: Bool) -> Bool {
        let node = ownerNode(owner)
        let reason: String?
        if closed {
            reason = "window-closed"
        } else if cancelled {
            reason = "task-cancelled"
        } else if gen != generation(of: owner) {
            reason = "stale-owner-generation"
        } else {
            reason = nil
        }
        if let reason {
            log.emit("effect", node: node, payload: ["phase": "rejected", "effect": effect, "reason": reason, "gen": gen])
            return false
        }
        log.emit("effect", node: node, payload: ["phase": "commit", "effect": effect, "gen": gen])
        return true
    }

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
        guard commitAllowed(effect, owner: owner, gen: gen, cancelled: Task.isCancelled) else {
            return nil
        }
        return value
    }

    func runToolbarInsert(seq: Int) async {
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
        let id = rowID(slot)
        guard let value = await runEffect("row-update", key: key, owner: .row(id)) else { return }
        editText(id, "Row \(slot) updated \(value)")
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
