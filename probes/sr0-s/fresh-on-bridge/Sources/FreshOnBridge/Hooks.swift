import Foundation
import SwiftRightRuntime
#if os(Windows)
import WinSDK
#endif

// Automation hook (SR0 R9): lets a driver perform the engine release of "insert row above" while a REAL IME
// composition is open, with no global input and no UI Automation action (a UIA Invoke would change focus and
// could end the composition). Two triggers, both in-process:
//   --release-event <name>  Windows named event (CreateEventW, auto-reset). The driver does
//                           [System.Threading.EventWaitHandle]::OpenExisting(<name>).Set(). A watcher thread
//                           waits on it and hops to the main queue (the queue the renderer's loop drains).
//   --release-file <path>   trigger file polled on the display tick; deleted when seen. Works on every OS.
// Each firing releases the oldest pending "insert-above" effect (else any "insert-toolbar-*") and logs one EVT
// line of kind "hook" carrying the focused field's composition state at the moment of release.

@MainActor
final class AutomationHooks {
    private let options: FixtureOptions
    private let engine: FakeEngine
    private let backend: BridgeBackend
    private let log: EventLog
    private(set) var fired = 0
    /// Set once a firing released a pending effect.
    private(set) var released = 0
    private var watcher: Thread?

    init(options: FixtureOptions, engine: FakeEngine, backend: BridgeBackend, log: EventLog) {
        self.options = options
        self.engine = engine
        self.backend = backend
        self.log = log
    }

    var isConfigured: Bool { options.releaseEvent != nil || options.releaseFile != nil }

    func start() {
        guard isConfigured else { return }
        log.emit("hook", node: "release-hook", payload: [
            "phase": "configured", "event": options.releaseEvent ?? "none", "file": options.releaseFile ?? "none",
        ])
        #if os(Windows)
        if let name = options.releaseEvent {
            let handle = name.withCString(encodedAs: UTF16.self) { CreateEventW(nil, false, false, $0) }
            if let handle {
                let box = HandleBox(handle: handle)
                let thread = Thread { [weak self] in
                    while true {
                        // Wake every 250 ms so a process exit never leaves the thread blocked forever.
                        if WaitForSingleObject(box.handle, 250) == WAIT_OBJECT_0 {
                            DispatchQueue.main.async {
                                MainActor.assumeIsolated { self?.fire(source: "event") }
                            }
                        }
                    }
                }
                thread.name = "release-hook"
                thread.start()
                watcher = thread
            } else {
                log.emit("hook", node: "release-hook", payload: ["phase": "event-create-failed", "event": name])
            }
        }
        #endif
    }

    /// Display tick: the file trigger.
    func poll() {
        guard let path = options.releaseFile, FileManager.default.fileExists(atPath: path) else { return }
        try? FileManager.default.removeItem(atPath: path)
        fire(source: "file")
    }

    func fire(source: String) {
        fired += 1
        let keys = engine.pendingKeys
        let key = keys.first { $0 == "insert-above" } ?? keys.first { $0.hasPrefix("insert-toolbar") }
        var payload: [String: Any] = [
            "phase": "release", "source": source, "key": key ?? "none", "pending": keys.joined(separator: ","),
        ]
        if let row = backend.focusedRow, let state = backend.textState(for: row) {
            payload["focused_row"] = row.uuidString
            payload["committed"] = state.committed
            payload["display"] = state.display
            payload["marked"] = state.markedRange.map { "\($0.location),\($0.length)" } ?? "none"
        }
        log.emit("hook", node: "release-hook", payload: payload)
        if let key, engine.release(key, value: 0) { released += 1 }
    }
}

#if os(Windows)
private struct HandleBox: @unchecked Sendable {
    let handle: HANDLE
}
#endif
