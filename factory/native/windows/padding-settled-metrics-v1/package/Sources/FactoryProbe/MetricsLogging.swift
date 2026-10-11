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
        var value = payload
        value["monotonicNS"] = DispatchTime.now().uptimeNanoseconds
        value["utc"] = formatter.string(from: Date())
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "FactoryMetricsLogSerialization", code: 1)
        }
        print("FACTORY_METRICS \(text)")
        fflush(stdout)
    }

    func snapshot(phase: String, source: String, window: BridgeWindow, expectedHWND: HWND? = nil,
                  bridgeMetrics: (width: UInt32, height: UInt32, scale: Float, active: Bool)? = nil,
                  extra: [String: Any] = [:]) throws -> FactoryOwnedClient {
        let abi: (width: UInt32, height: UInt32, scale: Float, active: Bool)
        if let bridgeMetrics { abi = bridgeMetrics } else { abi = try window.metrics() }
        let owned = try factoryOwnedClient(expected: expectedHWND)
        var payload = extra
        payload["record"] = "metrics-snapshot"
        payload["phase"] = phase
        payload["source"] = source
        payload["bridge"] = ["widthPx": abi.width, "heightPx": abi.height,
                              "scale": abi.scale, "active": abi.active]
        payload["ownedClient"] = ["widthPx": owned.size.width, "heightPx": owned.size.height,
                                   "dpi": owned.size.dpi, "scale": owned.size.scale,
                                   "logicalWidth": owned.size.logicalWidth,
                                   "logicalHeight": owned.size.logicalHeight]
        payload["pid"] = owned.pid
        payload["thread"] = owned.thread
        payload["hwnd"] = UInt(bitPattern: owned.hwnd)
        try emit(payload)
        return owned
    }

    func event(_ event: BridgeEvent, phase: String, source: String, window: BridgeWindow,
               expectedHWND: HWND?) throws -> FactoryOwnedClient {
        let raw: [String: Any] = [
            "kindRaw": event.kindRaw, "action": event.action, "window": event.window,
            "node": event.node, "snapshot": event.snapshot, "seq": event.seq,
            "arg": event.arg, "x": event.x, "y": event.y, "i0": event.i0,
            "i1": event.i1, "modifiers": event.modifiers, "text": event.text,
            "typed": event.typed
        ]
        return try snapshot(phase: phase, source: source, window: window,
                            expectedHWND: expectedHWND,
                            extra: ["event": raw, "eventKind": "windowMetrics"])
    }
}
