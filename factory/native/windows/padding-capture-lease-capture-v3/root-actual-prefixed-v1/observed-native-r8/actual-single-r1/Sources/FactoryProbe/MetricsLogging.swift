import Foundation
import WinSDK
import SwiftRightBridge

/// Source-only structured receipts for one real renderer callback path.
/// No poll/tick is promoted to a windowMetrics event.
@MainActor final class PaddingMetricsLog {
    private let formatter: ISO8601DateFormatter
    init() {
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    func emit(_ payload: [String: Any]) throws {
        let text = try factoryPaddingMetricsJSONText(payload,
            monotonicNS: DispatchTime.now().uptimeNanoseconds,
            utc: formatter.string(from: Date()))
        print("FACTORY_METRICS \(text)")
        fflush(stdout)
    }

    func snapshot(phase: String, source: String, window: BridgeWindow, expectedHWND: HWND? = nil,
                  bridgeMetrics: (width: UInt32, height: UInt32, scale: Float, active: Bool)? = nil,
                  extra: [String: Any] = [:], windowClosed: Bool = false) throws -> FactoryOwnedClient {
        let abi: (width: UInt32, height: UInt32, scale: Float, active: Bool)
        if let bridgeMetrics { abi = bridgeMetrics } else { abi = try window.metrics() }
        let owned = try factoryOwnedClient(expected: expectedHWND, phase: phase, windowClosed: windowClosed)
        let values = PaddingMetricsSnapshotValues(bridgeWidth: abi.width,
            bridgeHeight: abi.height, bridgeScale: abi.scale, active: abi.active,
            clientWidth: owned.size.width, clientHeight: owned.size.height,
            dpi: owned.size.dpi, clientScale: owned.size.scale,
            logicalWidth: Double(owned.size.logicalWidth),
            logicalHeight: Double(owned.size.logicalHeight),
            pid: owned.pid, thread: owned.thread, hwnd: UInt(bitPattern: owned.hwnd))
        let payload = factoryPaddingMetricsSnapshotPayload(values,
            phase: phase, source: source, extra: extra)
        try emit(payload)
        return owned
    }

    func event(_ event: BridgeEvent, phase: String, source: String, window: BridgeWindow,
               expectedHWND: HWND?, windowClosed: Bool = false) throws -> FactoryOwnedClient {
        let raw: [String: Any] = [
            "kindRaw": event.kindRaw, "action": event.action, "window": event.window,
            "node": event.node, "snapshot": event.snapshot, "seq": event.seq,
            "arg": event.arg, "x": Double(event.x), "y": Double(event.y), "i0": event.i0,
            "i1": event.i1, "modifiers": event.modifiers, "text": event.text,
            "typed": event.typed
        ]
        return try snapshot(phase: phase, source: source, window: window,
                            expectedHWND: expectedHWND,
                            extra: ["event": raw, "eventKind": "windowMetrics"], windowClosed: windowClosed)
    }
}
