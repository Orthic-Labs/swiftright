import Foundation
import Observation

// Shared editor model (same source on macOS and Windows). Foundation and Observation only: no view types,
// so the model compiles against either platform's view layer.

struct EditorRow: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var text: String
}

@MainActor
@Observable
final class EditorModel {
    /// Writable so the screen can bind `ForEach($model.rows)`; mutations that must persist go through the
    /// methods below, never through the binding (the TextField binding calls `editText`).
    var rows: [EditorRow] = []
    /// Last persistence failure, shown in the screen. Nil when the last load or save succeeded.
    private(set) var lastError: String?

    @ObservationIgnored private let store: RowStore?
    /// False after a failed load or without a data location: the file is then never written, so an
    /// unreadable file is not overwritten.
    @ObservationIgnored private var writable = true
    @ObservationIgnored private var focusSetter: ((UUID?) -> Void)?
    /// Set by the Windows backend: marks the runtime dirty when the model changes outside the runtime.
    @ObservationIgnored var onMutate: (() -> Void)?

    init(store: RowStore?) {
        self.store = store
        guard let store else {
            writable = false
            lastError = "no data location; rows are not saved"
            rows = Self.seedRows()
            return
        }
        do {
            if let loaded = try store.load() {
                rows = loaded
            } else {
                rows = Self.seedRows()
                persist()
            }
        } catch {
            writable = false
            lastError = "rows not loaded, not overwritten: \(error)"
            rows = Self.seedRows()
        }
    }

    static func seedRows() -> [EditorRow] {
        (1...5).map { EditorRow(id: UUID(), text: "Row \($0)") }
    }

    // MARK: Focus

    /// The screen registers its focus setter while it is built; the model never owns focus state itself.
    func registerFocus(_ setter: @escaping (UUID?) -> Void) {
        focusSetter = setter
    }

    func setFocus(_ id: UUID?) {
        focusSetter?(id)
    }

    // MARK: Edits

    /// Text write for one row: keystrokes (text store), AX SetValue and the TextField binding all land here.
    func editText(_ id: UUID, _ text: String) {
        guard let index = index(of: id), rows[index].text != text else { return }
        rows[index].text = text
        persist()
        onMutate?()
    }

    /// Inserts an empty row above the focused row (or at the top when nothing is focused) and focuses it.
    func insertAbove(focusedID: UUID?) {
        let position = focusedID.flatMap { index(of: $0) } ?? 0
        let row = EditorRow(id: UUID(), text: "")
        rows.insert(row, at: position)
        persist()
        onMutate?()
        setFocus(row.id)
    }

    func removeRow(_ id: UUID) {
        guard let index = index(of: id) else { return }
        rows.remove(at: index)
        persist()
        onMutate?()
    }

    /// SwiftUI onMove semantics: `destination` is an insertion index in the original array.
    func moveRow(from offsets: IndexSet, to destination: Int) {
        guard let source = offsets.first, offsets.count == 1, rows.indices.contains(source) else { return }
        let item = rows.remove(at: source)
        let target = destination > source ? destination - 1 : destination
        rows.insert(item, at: min(max(target, 0), rows.count))
        persist()
        onMutate?()
    }

    /// Up and Down buttons: one position per press, clamped at both ends.
    func nudgeRow(_ id: UUID, by delta: Int) {
        guard let index = index(of: id) else { return }
        let target = min(max(index + delta, 0), rows.count - 1)
        guard target != index else { return }
        moveRow(from: IndexSet(integer: index), to: target > index ? target + 1 : target)
    }

    // MARK: Helpers

    private func index(of id: UUID) -> Int? {
        rows.firstIndex { $0.id == id }
    }

    private func persist() {
        guard writable, let store else { return }
        do {
            try store.save(rows)
            lastError = nil
        } catch {
            lastError = "rows not saved: \(error)"
        }
    }
}
