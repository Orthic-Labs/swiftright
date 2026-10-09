#if os(Windows)
import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// SDK-owned Windows bootstrap: explicit renderer load, typed startup diagnostics, one root, and the
// bridge's run loop on the initial thread. Applications supply only the shared screen and model.
//
// Exit codes: 0 = window closed and shutdown completed, 1 = run failed, 78 = startup diagnostic
// (no window was created). Startup diagnostics are printed as SWR_STARTUP_ERROR / SLICE_STARTUP_ERROR lines.

@MainActor
func sliceAppWindowsMain() -> Int32 {
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

    guard let rowsURL = SliceAppData.rowsURL() else {
        print("SLICE_STARTUP_ERROR: LOCALAPPDATA is not set; cannot locate \(SliceAppData.rowsFileName)")
        return 78
    }

    let model = EditorModel(store: RowStore(url: rowsURL))
    let backend = BridgeBackend(bridge: bridge, model: model)
    bridge.textStore = SliceTextStore(backend: backend)
    bridge.onReady = { window in MainActor.assumeIsolated { backend.ready(window) } }
    bridge.onEvent = { event in MainActor.assumeIsolated { backend.handle(event) } }
    bridge.onWindowClosed = { MainActor.assumeIsolated { backend.closed() } }

    do {
        return try bridge.run(title: "SliceApp", width: 640, height: 480)
    } catch {
        print("SLICE_RUN_ERROR: \(error)")
        return 1
    }
}
#endif
