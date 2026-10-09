import AppKit
import CoreGraphics
import Foundation

// SliceApp QA probe (macOS). Compiled on the host by qa/drive-mac.sh (swiftc, headless) and copied into the disposable Tart VM,
// where it runs over ssh. It is never run against the host's own desktop. No Accessibility or Screen Recording permission is
// needed: window geometry comes from CGWindowListCopyWindowInfo (owner pid, bounds, layer), and the quit request is
// NSRunningApplication.terminate() (what the Dock's Quit sends), not an Apple event.
//
//   mac-probe state <bundleId>                   running?, pid, on-screen windows, windowShown
//   mac-probe quit <bundleId> <timeoutSec>       terminate(), wait for the process to go away
//   mac-probe rows <rows.json>                   schema, row count, row texts, sha256-free summary
//   mac-probe setrow <rows.json> <index> <text>  edit one row's text in the data file (between launches)
// Output: one JSON object on stdout.

func emit(_ object: [String: Any]) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

func windows(ownedBy pid: pid_t) -> [[String: Any]] {
    let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    var out: [[String: Any]] = []
    for info in infos {
        guard let owner = number(info[kCGWindowOwnerPID as String]), pid_t(owner) == pid else { continue }
        let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
        out.append([
            "layer": Int(number(info[kCGWindowLayer as String]) ?? -1),
            "width": number(bounds["Width"]) ?? 0,
            "height": number(bounds["Height"]) ?? 0,
        ])
    }
    return out
}

func state(_ bundleId: String) -> [String: Any] {
    // CGSessionCopyCurrentDictionary is nil when this process has no window-server session (a plain ssh login without an
    // Aqua session): window geometry would then be empty for the wrong reason, so report it.
    let gui = CGSessionCopyCurrentDictionary() != nil
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
        return ["running": false, "windowShown": false, "windows": [], "guiSession": gui]
    }
    let wins = windows(ownedBy: app.processIdentifier)
    let shown = wins.contains { ($0["layer"] as? Int) == 0 && (number($0["width"]) ?? 0) >= 200 && (number($0["height"]) ?? 0) >= 150 }
    return ["running": true, "pid": Int(app.processIdentifier), "windows": wins, "windowShown": shown, "guiSession": gui]
}

func quit(_ bundleId: String, timeout: Double) -> [String: Any] {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
        return ["terminated": true, "alreadyGone": true, "ms": 0]
    }
    let pid = app.processIdentifier
    let started = Date()
    let sent = app.terminate()
    var gone = false
    while Date().timeIntervalSince(started) < timeout {
        if kill(pid, 0) != 0 && errno == ESRCH { gone = true; break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return ["terminated": gone, "requestSent": sent, "alreadyGone": false, "ms": Int(Date().timeIntervalSince(started) * 1000)]
}

func loadRows(_ path: String) -> (root: [String: Any], rows: [[String: Any]])? {
    guard let data = FileManager.default.contents(atPath: path),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let rows = root["rows"] as? [[String: Any]] else { return nil }
    return (root, rows)
}

func rowsSummary(_ path: String) -> [String: Any] {
    guard let loaded = loadRows(path) else { return ["exists": FileManager.default.fileExists(atPath: path), "schema": NSNull(), "rowCount": 0, "texts": []] }
    return ["exists": true, "schema": loaded.root["schema"] ?? NSNull(), "rowCount": loaded.rows.count, "texts": loaded.rows.map { $0["text"] as? String ?? "" }]
}

func setRow(_ path: String, index: Int, text: String) -> [String: Any] {
    guard var loaded = loadRows(path), loaded.rows.indices.contains(index) else { return ["ok": false, "error": "rows.json missing or row index out of range"] }
    loaded.rows[index]["text"] = text
    var root = loaded.root
    root["rows"] = loaded.rows
    guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return ["ok": false, "error": "encode failed"] }
    do { try data.write(to: URL(fileURLWithPath: path), options: .atomic) } catch { return ["ok": false, "error": "\(error)"] }
    return ["ok": true]
}

let args = CommandLine.arguments
guard args.count >= 3 else { emit(["error": "usage: mac-probe state|quit|rows|setrow ..."]) }
switch args[1] {
case "state": emit(state(args[2]))
case "quit": emit(quit(args[2], timeout: args.count > 3 ? Double(args[3]) ?? 15 : 15))
case "rows": emit(rowsSummary(args[2]))
case "setrow":
    guard args.count >= 5, let index = Int(args[3]) else { emit(["error": "usage: mac-probe setrow <rows.json> <index> <text>"]) }
    emit(setRow(args[2], index: index, text: args[4]))
default: emit(["error": "unknown command \(args[1])"])
}
