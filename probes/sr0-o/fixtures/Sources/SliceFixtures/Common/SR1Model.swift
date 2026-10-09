import Foundation
import Observation

/// Row for the SR1 list fixtures (G3, G4). Identity is a deterministic UUID.
struct SR1Item: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
}

/// Model for the SR1 inventory fixtures G1..G8. Each screen owns one group of properties.
/// Binding writes made by SwiftUI are logged by the screens; model commands are logged here.
@MainActor
@Observable
final class SR1Model {
    let log: EventLog

    // Focus requests from the step driver, consumed by SR1Scaffold.
    var focusRequest: String?
    var focusRequestSeq = 0

    // G1 Toggle
    var toggleOn = false

    // G2 TextEditor
    var note = ""

    // G3 List(selection:) single and multiple
    let g3Rows: [SR1Item]
    var singleSelection: UUID?
    var multiSelection: Set<UUID> = []

    // G4 onDelete
    var g4Items: [SR1Item]
    var g4Selection: UUID?

    // G6 alert and confirmationDialog
    var alertShown = false
    var dialogShown = false

    // G8 disabled state
    var controlsLocked = false

    init(log: EventLog) {
        self.log = log
        self.g3Rows = (1...5).map { SR1Item(id: Self.sid(3, $0), title: "Item \($0)") }
        self.g4Items = (1...4).map { SR1Item(id: Self.sid(4, $0), title: "Entry \($0)") }
    }

    /// Deterministic identity for SR1 items. Group is the screen number, slot the row.
    nonisolated static func sid(_ group: Int, _ slot: Int) -> UUID {
        RowModel.rowID(fixture: 0x100 + group, slot: slot)
    }

    func requestFocus(_ id: String) {
        focusRequest = id
        focusRequestSeq += 1
    }

    /// Model-level delete command for G4 (the onDelete handler and this command are both logged).
    func deleteG4(_ offsets: IndexSet, source: String) {
        let removed = offsets.compactMap { g4Items.indices.contains($0) ? g4Items[$0].id.uuidString : nil }
        for index in offsets.sorted(by: >) where g4Items.indices.contains(index) {
            g4Items.remove(at: index)
        }
        log.emit("state", node: "g4/list", payload: [
            "op": "delete", "source": source, "removed": removed, "count": g4Items.count,
        ])
    }

    func menuAction(_ name: String) {
        log.emit("state", node: "g5", payload: ["op": "menu-action", "action": name])
    }
}
