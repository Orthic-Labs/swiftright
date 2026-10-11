import Foundation

// Headless Foundation-only fixtures; no window, renderer, native capture or event claim.
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "PaddingSerializerControl", code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]) }
}
let values = PaddingMetricsSnapshotValues(bridgeWidth: 320, bridgeHeight: 240,
    bridgeScale: 1, active: false, clientWidth: 2560, clientHeight: 1396,
    dpi: 240, clientScale: 2.5, logicalWidth: Double(CGFloat(1024)),
    logicalHeight: Double(CGFloat(558.4)), pid: 50692, thread: 57664, hwnd: 4657170)
let raw: [String: Any] = ["kindRaw": UInt32(7), "action": UInt32(0),
    "window": UInt64.max, "node": UInt64(0), "snapshot": UInt64(0),
    "seq": UInt64(1), "arg": UInt64(0), "x": Double(Float(0)), "y": Double(Float(0)),
    "i0": Int32(2560), "i1": Int32(1396), "modifiers": UInt32(0),
    "text": "", "typed": ""]
do {
    let ready = factoryPaddingMetricsSnapshotPayload(values, phase: "onReady", source: "Bridge.onReady")
    let event = factoryPaddingMetricsSnapshotPayload(values, phase: "first-window-metrics-event",
        source: "Bridge.onEvent", extra: ["event": raw, "eventKind": "windowMetrics"])
    let firstLayout: [String: Any] = ["record": "first-layout", "phase": "first-commit-complete",
        "source": "BridgeWindow.commit", "ordering": "onReady-before-first-layout",
        "pid": values.pid, "thread": values.thread, "hwnd": values.hwnd,
        "dpi": values.dpi, "scale": Double(values.clientScale),
        "windowMetricsEventSeen": false, "version": UInt64(1)]
    let close: [String: Any] = ["record": "window-metrics-status", "phase": "window-closed",
        "source": "Bridge.onWindowClosed", "status": "held-missing-actual-windowMetrics-event",
        "pid": values.pid, "thread": values.thread, "hwnd": values.hwnd,
        "dpi": values.dpi, "scale": Double(values.clientScale), "firstLayoutLogged": true]
    let error: [String: Any] = ["record": "control-error-fixture", "domain": "FactoryMetricsLogSerialization",
        "code": Int(1), "message": "control only"]
    for (index, payload) in [ready, event, firstLayout, close, error].enumerated() {
        let text = try factoryPaddingMetricsJSONText(payload,
            monotonicNS: 71396257456400, utc: "2026-10-11T08:43:22.114Z")
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        try require(object is [String: Any], "Round trip object failed")
        if index == 1 { try require(text.contains("18446744073709551615"), "UInt64 identity precision lost") }
        print("SERIALIZER_CONTROL_RECORD \(index) \(text)")
    }
    do {
        _ = try factoryPaddingMetricsJSONText(["bad": Double.infinity], monotonicNS: 1, utc: "control")
        throw NSError(domain: "PaddingSerializerControl", code: 2)
    } catch let error as NSError {
        try require(error.domain == "FactoryMetricsLogSerialization", "Invalid JSON did not fail closed")
    }
    let legacy: [String: Any] = ["logicalWidth": CGFloat(1024), "logicalHeight": CGFloat(558.4)]
    print("SERIALIZER_CONTROL_LEGACY_CGFLOAT_VALID \(JSONSerialization.isValidJSONObject(legacy))")
    print("SERIALIZER_CONTROL_PASS records=5 failClosed=true nativeLaunches=0")
} catch {
    fputs("SERIALIZER_CONTROL_FAIL \(error)\n", stderr)
    exit(1)
}
