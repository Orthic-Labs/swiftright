import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// FreshOnBridge (SR0-S): fixture F1 on the fresh runtime through bridge ABI v0.
// Usage: FreshOnBridge.exe [--self-test]
//   --self-test  scripted F1 check; the input is driven from outside (scripts/drive-fresh.ps1).
//   no flag      interactive run until the window closes.
// Exit: 0 = pass (or interactive close), 1 = failed assertion or run error, 78 = startup diagnostic.

@MainActor
func runFreshOnBridge(selfTest: Bool) -> Int32 {
    let bridge: Bridge
    do {
        bridge = try Bridge.load()
    } catch BridgeError.startup(let message) {
        print(message)
        return 78
    } catch {
        print("SWR_STARTUP_ERROR: \(error)")
        return 78
    }

    let log = EventLog()
    let engine = FakeEngine(log: log)
    let model = RowModel(log: log, engine: engine)
    let backend = BridgeBackend(bridge: bridge, model: model, log: log)
    bridge.textStore = FreshTextStore(backend: backend)
    let test: SelfTest? = selfTest
        ? SelfTest(bridge: bridge, backend: backend, model: model, log: log, engine: engine)
        : nil
    test?.requestQuit = { bridge.requestQuit() }
    backend.afterInput = { test?.advance() }

    bridge.onReady = { win in MainActor.assumeIsolated { backend.ready(win) } }
    bridge.onEvent = { ev in MainActor.assumeIsolated { backend.handle(ev) } }
    bridge.onTick = { _, _ in MainActor.assumeIsolated { backend.tick(); test?.tick() } }
    bridge.onWindowClosed = { MainActor.assumeIsolated { backend.closed() } }

    do {
        try bridge.run(title: "SwiftRight FreshOnBridge F1", width: 640, height: 480)
    } catch {
        print("run failed: \(error)")
        fflush(stdout)
        return 1
    }
    guard let test else { return 0 }
    if !test.finished {
        print("SELFTEST F1-bridge: FAIL (window closed before the scripted run finished)")
        return 1
    }
    return test.passed ? 0 : 1
}

let arguments = CommandLine.arguments
let status = MainActor.assumeIsolated { runFreshOnBridge(selfTest: arguments.contains("--self-test")) }
fflush(stdout)
exit(status)
