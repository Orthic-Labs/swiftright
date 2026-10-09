import Foundation

// Row persistence: one JSON file in the per-user app-data directory. Schema 1 is the on-disk contract that
// upgrade and rollback builds must both read (PACKAGING.md). Writes are atomic: a crash leaves the old file.

enum SliceAppData {
    static let directoryName = "SliceApp"
    static let rowsFileName = "rows.json"

    /// macOS: ~/Library/Application Support/SliceApp/rows.json.
    /// Windows: %LOCALAPPDATA%\SliceApp\rows.json (outside the MSIX install folder, so it survives uninstall).
    static func rowsURL() -> URL? {
        #if os(Windows)
        guard let base = ProcessInfo.processInfo.environment["LOCALAPPDATA"], !base.isEmpty else { return nil }
        let root = URL(fileURLWithPath: base, isDirectory: true)
        #else
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        #endif
        return root.appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(rowsFileName, isDirectory: false)
    }
}

struct RowFile: Codable, Sendable {
    var schema: Int
    var rows: [EditorRow]
}

enum RowStoreError: Error, CustomStringConvertible {
    case unsupportedSchema(Int)

    var description: String {
        switch self {
        case .unsupportedSchema(let value): return "unsupported rows schema \(value) (expected 1)"
        }
    }
}

struct RowStore: Sendable {
    static let schemaVersion = 1
    let url: URL

    /// Nil when the file does not exist yet (first run). Throws when the file exists but cannot be read.
    func load() throws -> [EditorRow]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(RowFile.self, from: data)
        guard file.schema == Self.schemaVersion else { throw RowStoreError.unsupportedSchema(file.schema) }
        return file.rows
    }

    func save(_ rows: [EditorRow]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(RowFile(schema: Self.schemaVersion, rows: rows))
        try data.write(to: url, options: .atomic)
    }
}
