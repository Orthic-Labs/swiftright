import AppKit
import Foundation
import SwiftUI

// F1-lite fixture. Row ids are stable UUIDs; text fields carry identifier row/<uuid>/field.

let eventsURL = FileManager.default.temporaryDirectory.appendingPathComponent("sr0-fixture-events.jsonl")

@MainActor
func logEvent(_ fields: [String: Any]) {
    var f = fields
    f["ts"] = String(format: "%.6f", Date().timeIntervalSince1970)
    guard let data = try? JSONSerialization.data(withJSONObject: f, options: [.sortedKeys]) else { return }
    var line = data
    line.append(0x0A)
    if !FileManager.default.fileExists(atPath: eventsURL.path) {
        FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
    }
    if let h = try? FileHandle(forWritingTo: eventsURL) {
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: line)
        try? h.close()
    }
}

struct Row: Identifiable, Equatable {
    let id: UUID
    var text: String
}

@MainActor
@Observable
final class Store {
    var rows: [Row]

    init() {
        rows = (1...10).map { n in
            Row(id: UUID(uuidString: String(format: "5A5A5A5A-0000-4000-8000-%012d", n))!, text: "Row \(n)")
        }
    }

    func insertAbove() {
        let r = Row(id: UUID(), text: "Inserted")
        rows.insert(r, at: 0)
        logEvent(["ev": "insert", "index": 0, "row": r.id.uuidString])
    }
}

@main
struct SR0FixtureApp: App {
    @State private var store = Store()

    init() {
        // Reset the in-process event log for this run.
        FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        Window("SR0 Fixture", id: "main") {
            ContentView(store: store)
        }
    }
}

struct ContentView: View {
    @Bindable var store: Store

    var body: some View {
        List {
            ForEach($store.rows) { $row in
                let rowID = $row.wrappedValue.id.uuidString
                TextField("Row", text: $row.text)
                    .accessibilityIdentifier("row/\(rowID)/field")
                    .onAppear { logEvent(["ev": "appear", "row": rowID, "text": $row.wrappedValue.text]) }
                    .onDisappear { logEvent(["ev": "disappear", "row": rowID]) }
                    .onChange(of: $row.wrappedValue.text) { _, new in
                        logEvent(["ev": "text", "row": rowID, "text": new])
                    }
            }
        }
        .toolbar {
            Button("Insert above") { store.insertAbove() }
                .accessibilityIdentifier("toolbar/insert")
        }
        .frame(minWidth: 420, minHeight: 520)
        .onAppear { NSApplication.shared.activate() }
    }
}
